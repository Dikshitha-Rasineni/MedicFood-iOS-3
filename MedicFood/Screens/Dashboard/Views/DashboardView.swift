import SwiftUI

/// Home B — today's doses.
///
/// The medication is on the first screen rather than a tap away. No navigation
/// bar: the greeting *is* the title, which is what buys the 40pt display type
/// the room to work.
struct DashboardView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: DashboardViewModel?
    @State private var isAddingMedicine = false

    var body: some View {
        let model = viewModel ?? DashboardViewModel(services: services)

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(model)

                if model.totalCount > 0 {
                    ProgressCard(
                        taken: model.takenCount,
                        total: model.totalCount,
                        progress: model.progress
                    )
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                }

                if model.isLoading && model.items.isEmpty {
                    ProgressView()
                        .tint(Theme.Colors.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if model.isEmpty {
                    NothingDueView { isAddingMedicine = true }
                } else {
                    ForEach(model.groupedBySlot, id: \.slot) { group in
                        SlotSection(slot: group.slot, items: group.items, model: model)
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.Colors.page.ignoresSafeArea())
        .scrollIndicators(.hidden)
        // Deliberately not `navigationBarHidden`: this is pushed from Home
        // now, and hiding the bar takes the back button with it. An empty
        // inline title keeps the chevron without stealing the header's room.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingMedicine) {
            NavigationStack { AddMedicineView() }
        }
        .refreshable { await model.load() }
        .task {
            viewModel = model
            await model.load()
        }
        .onChange(of: isAddingMedicine) { _, isPresented in
            // Reload after the sheet closes, so a new medicine shows up.
            if !isPresented { Task { await model.load() } }
        }
    }

    // MARK: Header

    private func header(_ model: DashboardViewModel) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(model.isToday ? model.greeting : "Schedule")
                    .font(Theme.Typography.display)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Button { isAddingMedicine = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.primary, in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Add medicine")
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Progress

/// Progress through the day's doses.
///
/// The number treatment is the point: one big rounded numeral against small
/// regular text, rather than one flat string.
private struct ProgressCard: View {
    let taken: Int
    let total: Int
    let progress: Double

    @State private var shownProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(taken)")
                        .font(Theme.Typography.numeral(40))
                        .monospacedDigit()
                        .tracking(Theme.Typography.displayTracking)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())

                    Text("of \(total) taken today")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)

                Text("\(Int(progress * 100))%")
                    .font(Theme.Typography.numeral(22))
                    .monospacedDigit()
                    // Deliberately *not* the adherence grade scale. This is
                    // "how far through today", not a score — colouring 0% red
                    // at breakfast reports a failure that hasn't happened.
                    // The grade colours stay on the Adherence screen.
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .contentTransition(.numericText())
            }

            Spacer().frame(height: 12)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface)
                    Capsule()
                        .fill(Theme.Colors.brand)
                        .frame(width: max(0, geo.size.width * shownProgress))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .cardSurface()
        .onChange(of: progress, initial: true) { _, new in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shownProgress = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(taken) of \(total) doses taken today, \(Int(progress * 100)) percent")
    }
}

// MARK: - Slot section

/// One time-of-day group, e.g. everything due in the morning.
private struct SlotSection: View {
    let slot: DoseSlot
    let items: [DashboardViewModel.DoseItem]
    let model: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(slot.displayName)
                    .sectionLabelStyle()
                Spacer()
                Text(timeLabel)
                    .font(Theme.Typography.numeral(15))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.top, 4)

            ForEach(items) { item in
                DoseRow(item: item, model: model)
            }
        }
    }

    private var timeLabel: String {
        var components = DateComponents()
        components.hour = slot.defaultTime.hour
        components.minute = slot.defaultTime.minute
        guard let time = Calendar.current.date(from: components) else { return "" }
        return time.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Empty state

private struct NothingDueView: View {
    let addMedicine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmptyIllustration()
                .frame(width: 180, height: 150)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)

            Spacer().frame(height: 26)

            Text("Nothing due today")
                .font(Theme.Typography.screenTitle)
                .tracking(Theme.Typography.screenTitleTracking)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer().frame(height: 8)

            Text("Add a medicine and MedicFood will remind you at the right times, with food notes attached.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 24)

            Button(action: addMedicine) {
                Text("Add medicine")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.controlHeight)
                    .background(
                        Theme.Colors.primary,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(PressableCardStyle())
        }
    }
}

/// Built from plain shapes in palette colours — no asset, nothing to go stale.
private struct EmptyIllustration: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.Colors.surface)
                .frame(width: 140, height: 118)
                .offset(x: 20, y: 14)

            Circle()
                .strokeBorder(Theme.Colors.decorative, lineWidth: 3)
                .frame(width: 76, height: 76)
                .offset(x: 52, y: 38)

            Capsule()
                .fill(Theme.Colors.decorative)
                .frame(width: 3, height: 26)
                .offset(x: 88, y: 52)

            Capsule()
                .fill(Theme.Colors.decorative)
                .frame(width: 22, height: 3)
                .offset(x: 88, y: 74)

            Circle()
                .fill(Theme.Colors.decorative)
                .frame(width: 34, height: 34)
                .offset(x: 132, y: 96)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
