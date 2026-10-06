import SwiftUI

/// How well the user is keeping to the schedule.
struct AdherenceView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: AdherenceViewModel?

    /// A day counts as kept when most of its doses were taken. Used only to
    /// decide which bars are worth colouring.
    private static let dayTarget = 0.8

    var body: some View {
        let model = viewModel ?? AdherenceViewModel(services: services)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Progress")
                    .font(Theme.Typography.screenTitle)
                    .tracking(Theme.Typography.screenTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, 8)

                periodPicker(model)

                if model.stats.total == 0 {
                    // Nothing recorded yet is not 0% adherence. Showing a red
                    // zero to someone who has simply not started reads as a
                    // failure they did not earn.
                    EmptyStateView(
                        symbol: "chart.bar",
                        title: "Nothing recorded yet",
                        message: "Once you start marking doses taken, your progress shows up here."
                    )
                    .padding(.top, 12)
                } else {
                    headline(model)
                    chart(model)
                    breakdown(model)
                }
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.bottom, 32)
            .animation(Theme.Motion.cardAppear, value: model.period)
        }
        .background(Theme.Colors.page)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task {
            viewModel = model
            await model.load()
        }
    }

    // MARK: - Period

    private func periodPicker(_ model: AdherenceViewModel) -> some View {
        Picker("Period", selection: Binding(get: { model.period }, set: { model.period = $0 })) {
            ForEach(AdherenceViewModel.Period.allCases) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Headline

    /// The one number the screen exists to say, as a ring.
    ///
    /// The figure itself is set in ink rather than in the status colour — the
    /// ring beside it already carries that, and a large coloured numeral on the
    /// green page is exactly the "muddy at size" problem Theme warns about.
    private func headline(_ model: AdherenceViewModel) -> some View {
        VStack(spacing: 14) {
            ProgressRing(rate: model.stats.rate) {
                VStack(spacing: 0) {
                    Text("\(model.stats.percentage)")
                        .font(Theme.Typography.numeral(40))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            VStack(spacing: 8) {
                StatusChip(
                    symbol: statusSymbol(model.stats.rate),
                    text: model.headline,
                    tint: Theme.Colors.adherence(model.stats.rate)
                )

                Text("\(model.stats.taken) of \(model.stats.total) doses taken")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if model.currentStreak > 0 {
                    Label(
                        "\(model.currentStreak) day\(model.currentStreak == 1 ? "" : "s") in a row",
                        systemImage: "flame.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.skipped)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .shadow(
            color: Theme.Metrics.shadow.color,
            radius: Theme.Metrics.shadow.radius,
            y: Theme.Metrics.shadow.y
        )
    }

    private func statusSymbol(_ rate: Double) -> String {
        switch rate {
        case 0.9...:    "checkmark.seal.fill"
        case 0.7..<0.9: "hand.thumbsup.fill"
        case 0.5..<0.7: "exclamationmark.circle.fill"
        default:        "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Chart

    private func chart(_ model: AdherenceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily")
                    .font(Theme.Typography.cardTitle)
                    .tracking(Theme.Typography.cardTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                // A legend, because two fills carry meaning. One series would
                // need none; two always does.
                HStack(spacing: 10) {
                    legendKey(color: Theme.Colors.brand, label: "On track")
                    legendKey(color: Theme.Colors.missed.opacity(0.85), label: "Short")
                }
            }

            DailyBars(
                columns: model.bars.map {
                    DayColumn(
                        date: $0.date,
                        rate: $0.rate,
                        hasDoses: $0.hasDoses,
                        isShortfall: $0.hasDoses && $0.rate < Self.dayTarget
                    )
                },
                showsWeekdays: model.period == .week
            )
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .shadow(
            color: Theme.Metrics.shadow.color,
            radius: Theme.Metrics.shadow.radius,
            y: Theme.Metrics.shadow.y
        )
    }

    private func legendKey(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Breakdown

    private func breakdown(_ model: AdherenceViewModel) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatTile(symbol: "checkmark.circle.fill", title: "Taken", count: model.stats.taken, tint: Theme.Colors.taken)
            StatTile(symbol: "arrow.uturn.right.circle.fill", title: "Dismissed", count: model.stats.skipped, tint: Theme.Colors.skipped)
            StatTile(symbol: "exclamationmark.circle.fill", title: "Missed", count: model.stats.missed, tint: Theme.Colors.missed)
            StatTile(symbol: "clock.fill", title: "Upcoming", count: model.upcoming, tint: Theme.Colors.pending)
        }
    }
}

#Preview {
    NavigationStack { AdherenceView() }
        .environment(ServiceContainer.mock())
}
