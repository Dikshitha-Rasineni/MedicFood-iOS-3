import SwiftUI

/// Look up a drug and see what food affects it.
struct MedicineSearchView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: MedicineSearchViewModel?

    var body: some View {
        let model = viewModel ?? MedicineSearchViewModel(services: services)

        List {
            if let error = model.errorMessage {
                ErrorBanner(message: error).listRowSeparator(.hidden)
            }

            ForEach(model.results) { drug in
                NavigationLink(value: drug) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drug.name).font(.body.weight(.medium))
                        if let synonym = drug.synonym {
                            Text(synonym)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .overlay {
            if model.isSearching {
                ProgressView()
            } else if model.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    message: "Try the generic name — for example paracetamol rather than a brand."
                )
            } else if !model.hasSearched {
                EmptyStateView(
                    symbol: "cross.case",
                    title: "Look up a medicine",
                    message: "Search for what it does, how to take it, and which foods to watch out for."
                )
            }
        }
        .searchable(
            text: Binding(get: { model.query }, set: { model.query = $0 }),
            prompt: "Medicine name"
        )
        .onChange(of: model.query) { _, _ in model.searchDebounced() }
        .navigationTitle("Search")
        .navigationDestination(for: DrugInfo.self) { drug in
            DrugDetailView(drug: drug, model: model)
        }
        .onAppear { viewModel = model }
    }
}

/// What a drug is, and what not to eat with it.
struct DrugDetailView: View {
    let drug: DrugInfo
    let model: MedicineSearchViewModel

    var body: some View {
        List {
            if let purpose = drug.purpose {
                Section("What it is for") { Text(purpose) }
            }

            if let guidance = drug.dosageGuidance {
                Section("How to take it") { Text(guidance) }
            }

            if let warnings = drug.warnings {
                Section("Warnings") {
                    Text(warnings).foregroundStyle(.red)
                }
            }

            Section {
                if model.isLoadingInteractions {
                    ProgressView()
                } else if model.interactions.isEmpty {
                    Text("No specific food interactions on record.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.interactions) { interaction in
                        InteractionRow(interaction: interaction)
                    }
                }
            } header: {
                Text("Food and drink")
            } footer: {
                Text("General information only. Always follow your doctor or pharmacist.")
            }

            Section {
                LabeledContent("RxNorm ID", value: drug.rxcui)
                if let form = drug.form {
                    LabeledContent("Form", value: form)
                }
            }
        }
        .navigationTitle(drug.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadInteractions(for: drug) }
    }
}

private struct InteractionRow: View {
    let interaction: FoodInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(interaction.food).font(.body.weight(.medium))
                Spacer()
                Text(interaction.severity.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.15))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
            Text(interaction.effect)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch interaction.severity {
        case .avoid:   .red
        case .caution: .orange
        case .minor:   .secondary
        }
    }
}

#Preview {
    NavigationStack { MedicineSearchView() }
        .environment(ServiceContainer.mock())
}
