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
            if let error = model.errorMessage {
                ErrorBanner(message: error).listRowSeparator(.hidden)
            }

            if !model.active.isEmpty {
                Section("Active") {
                    ForEach(model.active) { medicine in
                        NavigationLink(value: medicine) {
                            MedicineRow(medicine: medicine)
                        }
                        .listRowBackground(Theme.Colors.cardSurface)
                    }
                    .onDelete { offsets in
                        Task {
                            for index in offsets { await model.delete(model.active[index]) }
                        }
                    }
                }
            }

            if !model.inactive.isEmpty {
                Section("Paused") {
                    ForEach(model.inactive) { medicine in
                        NavigationLink(value: medicine) {
                            MedicineRow(medicine: medicine).opacity(0.6)
                        }
                        .listRowBackground(Theme.Colors.cardSurface)
                    }
                }
            }
        }
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
        .navigationTitle("Medicines")
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
        HStack(spacing: 12) {
            MedicineThumbnail(
                fileName: medicine.frontImagePath ?? medicine.backImagePath,
                form: medicine.form,
                size: 56
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(medicine.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(medicine.dosage) · \(medicine.frequencyDescription)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if medicine.isActive, let next = medicine.nextDose() {
                    Text("Next dose \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.primary)
                } else if !medicine.isActive {
                    Text("Inactive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.skipped)
                }

                Text(medicine.foodInstruction.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { MedicineListView() }
        .environment(ServiceContainer.mock())
}
