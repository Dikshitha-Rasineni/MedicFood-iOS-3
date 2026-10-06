import SwiftUI

/// Every medicine on the user's list.
struct MedicineListView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: MedicineListViewModel?
    @State private var isAdding = false
    @State private var isScanning = false

    var body: some View {
        let model = viewModel ?? MedicineListViewModel(services: services)

        List {
            // Drawn in-page, like Progress and Search. UINavigationBar stopped
            // rendering a large title once the bar was made opaque, and the
            // app now has one house style for screen titles anyway.
            Text("Medicines")
                .font(Theme.Typography.screenTitle)
                .tracking(Theme.Typography.screenTitleTracking)
                .foregroundStyle(Theme.Colors.textPrimary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: Theme.Metrics.pageMargin, bottom: 4, trailing: Theme.Metrics.pageMargin))

            if let error = model.errorMessage {
                ErrorBanner(message: error).listRowSeparator(.hidden)
            }

            if !model.active.isEmpty {
                Section {
                    ForEach(model.active) { medicine in
                        NavigationLink(value: medicine) {
                            MedicineRow(medicine: medicine)
                        }
                        .cardRow()
                    }
                    .onDelete { offsets in
                        Task {
                            for index in offsets { await model.delete(model.active[index]) }
                        }
                    }
                } header: {
                    Text("Active").sectionLabelStyle()
                }
            }

            if !model.inactive.isEmpty {
                Section {
                    ForEach(model.inactive) { medicine in
                        NavigationLink(value: medicine) {
                            MedicineRow(medicine: medicine).opacity(0.65)
                        }
                        .cardRow()
                    }
                } header: {
                    Text("Paused").sectionLabelStyle()
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.page.ignoresSafeArea())
        .overlay {
            if model.isEmpty {
                EmptyStateView(
                    symbol: "pills",
                    title: "No medicines yet",
                    message: "Add what you have been prescribed and MedicFood will remind you.",
                    actionTitle: "Add medicine",
                    action: { isAdding = true }
                )
            }
        }
        .searchable(text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Medicine.self) { medicine in
            MedicineDetailView(medicine: medicine, model: model)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    MedicineSearchView()
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .accessibilityLabel("Look up a medicine")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add one medicine", systemImage: "plus")
                    }
                    Button {
                        isScanning = true
                    } label: {
                        Label("Add a prescription", systemImage: "text.viewfinder")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { AddMedicineView() }
        }
        .navigationDestination(isPresented: $isScanning) {
            PrescriptionScannerView()
        }
        .onChange(of: isScanning) { _, isPresented in
            if !isPresented { Task { await model.load() } }
        }
        .task {
            viewModel = model
            await model.load()
        }
        .onChange(of: isAdding) { _, isPresented in
            if !isPresented { Task { await model.load() } }
        }
    }
}

struct MedicineRow: View {
    let medicine: Medicine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MedicineThumbnail(
                    fileName: medicine.frontImagePath ?? medicine.backImagePath,
                    form: medicine.form,
                    size: 52
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(medicine.name)
                        .font(Theme.Typography.cardTitle)
                        .tracking(Theme.Typography.cardTitleTracking)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("\(medicine.dosage) · \(medicine.frequencyDescription)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if medicine.isActive, let next = medicine.nextDose() {
                    // The one fact worth reading at a glance on this screen.
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.8))
                        Text(next.formatted(date: .omitted, time: .shortened))
                            .font(Theme.Typography.numeral(15))
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
            }

            HStack(spacing: 6) {
                if !medicine.isActive {
                    tag(medicine.isActive ? "Active" : "Paused", symbol: "pause.circle.fill", tint: Theme.Colors.skipped)
                }
                tag(medicine.foodInstruction.displayName, symbol: "fork.knife", tint: Theme.Colors.primary)
                tag(medicine.timingDescription, symbol: "clock", tint: Theme.Colors.primary)

                Spacer(minLength: 0)
            }

            // A fixed course has an end; showing how far through it is turns a
            // list entry into something you can act on ("two days left").
            if medicine.isActive, let remaining = daysRemaining {
                courseProgress(remaining)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.1))
        .clipShape(Capsule())
    }

    private var daysRemaining: Int? {
        guard let end = medicine.endDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now), to: end
        ).day
        guard let days, days >= 0 else { return nil }
        return days + 1
    }

    private func courseProgress(_ remaining: Int) -> some View {
        let total = medicine.durationDays ?? remaining
        let done = max(0, total - remaining)
        let fraction = total == 0 ? 0 : Double(done) / Double(total)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Course")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(remaining == 1 ? "1 day left" : "\(remaining) days left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface)
                    Capsule()
                        .fill(Theme.Colors.brand)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

/// A List row that carries a card: no separator, no grey selection fill, and
/// the page colour behind it — so `List` keeps swipe-to-delete while the rows
/// look like the cards used everywhere else.
private extension View {
    func cardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: Theme.Metrics.pageMargin, bottom: 5, trailing: Theme.Metrics.pageMargin))
    }
}

#Preview {
    NavigationStack { MedicineListView() }
        .environment(ServiceContainer.mock())
}
