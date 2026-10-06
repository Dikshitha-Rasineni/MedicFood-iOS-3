import SwiftUI

/// How well the user is keeping to the schedule.
struct AdherenceView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: AdherenceViewModel?

    var body: some View {
        let model = viewModel ?? AdherenceViewModel(services: services)

        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: Binding(get: { model.period }, set: { model.period = $0 })) {
                    ForEach(AdherenceViewModel.Period.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                headline(model)
                chart(model)
                breakdown(model)
            }
            .padding(16)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Progress")
        .refreshable { await model.load() }
        .task {
            viewModel = model
            await model.load()
        }
    }

    private func headline(_ model: AdherenceViewModel) -> some View {
        Card {
            VStack(spacing: 8) {
                Text("\(model.stats.percentage)%")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.adherence(model.stats.rate))

                Text(model.headline)
                    .font(.headline)

                Text("\(model.stats.taken) of \(model.stats.total) doses taken")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.currentStreak > 0 {
                    Label(
                        "\(model.currentStreak) day\(model.currentStreak == 1 ? "" : "s") in a row",
                        systemImage: "flame.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A plain bar chart. Deliberately hand-drawn with `Rectangle` rather than
    /// pulled from Swift Charts — one fewer framework for a chart this simple,
    /// and it renders identically on every supported iOS version.
    private func chart(_ model: AdherenceViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Daily")
                    .font(.headline)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(model.bars) { bar in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bar.hasDoses
                                      ? Theme.Colors.adherence(bar.rate)
                                      : Color.secondary.opacity(0.15))
                                .frame(height: max(4, bar.rate * 90) + (bar.hasDoses ? 0 : 0))
                                .frame(maxHeight: 90, alignment: .bottom)

                            if model.period == .week {
                                Text(bar.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: model.period == .week ? 110 : 94, alignment: .bottom)
            }
        }
    }

    private func breakdown(_ model: AdherenceViewModel) -> some View {
        Card {
            VStack(spacing: 12) {
                row("Taken", count: model.stats.taken, tint: Theme.Colors.taken, symbol: "checkmark.circle.fill")
                Divider()
                row("Dismissed", count: model.stats.skipped, tint: Theme.Colors.skipped, symbol: "arrow.uturn.right.circle.fill")
                Divider()
                row("Missed", count: model.stats.missed, tint: Theme.Colors.missed, symbol: "exclamationmark.circle.fill")
                Divider()
                row("Upcoming", count: model.upcoming, tint: Theme.Colors.pending, symbol: "clock.fill")
            }
        }
    }

    private func row(_ title: String, count: Int, tint: Color, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title)
            Spacer()
            Text("\(count)").font(.body.weight(.semibold).monospacedDigit())
        }
    }
}

#Preview {
    NavigationStack { AdherenceView() }
        .environment(ServiceContainer.mock())
}
