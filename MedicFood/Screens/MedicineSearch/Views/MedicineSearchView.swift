import SwiftUI

/// Look up a drug and see what food affects it.
struct MedicineSearchView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: MedicineSearchViewModel?

    var body: some View {
        let model = viewModel ?? MedicineSearchViewModel(services: services)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // Drawn here rather than left to `navigationTitle`, so it
                // matches the green title every other rebuilt screen uses and
                // does not depend on UINavigationBar's large-title behaviour.
                Text("Search")
                    .font(Theme.Typography.screenTitle)
                    .tracking(Theme.Typography.screenTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.bottom, 4)

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                        .transition(.opacity)
                }

                ForEach(model.results) { drug in
                    NavigationLink(value: drug) {
                        DrugResultRow(drug: drug)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(Theme.Motion.cardAppear, value: model.results)
        }
        .background(Theme.Colors.page)
        .scrollIndicators(.hidden)
        .overlay {
            if model.isSearching {
                ProgressView()
                    .tint(Theme.Colors.primary)
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DrugInfo.self) { drug in
            DrugDetailView(drug: drug, model: model)
        }
        .onAppear { viewModel = model }
    }
}

/// One search hit.
private struct DrugResultRow: View {
    let drug: DrugInfo

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: "pills.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text(drug.name)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)

                if let detail = drug.synonym ?? drug.purpose {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)
            SettingsChevron()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// What a drug is, and what not to eat with it.
struct DrugDetailView: View {
    let drug: DrugInfo
    let model: MedicineSearchViewModel

    var body: some View {
        SettingsPage(title: drug.name) {
            if let purpose = drug.purpose {
                SettingsSection(title: "What it is for") {
                    prose(purpose)
                }
            }

            if let guidance = drug.dosageGuidance {
                SettingsSection(title: "How to take it") {
                    prose(guidance)
                }
            }

            if let warnings = drug.warnings {
                NoticeCard(symbol: "exclamationmark.triangle.fill", text: warnings, tint: Theme.Colors.missed)
            }

            SettingsSection(
                title: "Food and drink",
                footer: "General information only. Always follow your doctor or pharmacist."
            ) {
                if model.isLoadingInteractions {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.Colors.primary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if model.interactions.isEmpty {
                    prose("No specific food interactions on record.")
                } else {
                    ForEach(Array(model.interactions.enumerated()), id: \.element.id) { index, interaction in
                        if index > 0 { SettingsDivider(inset: 14) }
                        InteractionRow(interaction: interaction)
                    }
                }
            }

            SettingsSection(title: "Reference") {
                SettingsRow(symbol: "number", title: "RxNorm ID") {
                    SettingsValue(text: drug.rxcui)
                }
                if let form = drug.form {
                    SettingsDivider()
                    SettingsRow(symbol: "pills", title: "Form") {
                        SettingsValue(text: form)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadInteractions(for: drug) }
    }

    private func prose(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

private struct InteractionRow: View {
    let interaction: FoodInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(interaction.food)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 8)

                Text(interaction.severity.displayName)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }

            Text(interaction.effect)
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Severity colours come from `Theme`'s status scale, not from SwiftUI's
    /// `.red`/`.orange` — those sit outside the palette and read as a
    /// different app's warning.
    private var tint: Color {
        switch interaction.severity {
        case .avoid:   Theme.Colors.missed
        case .caution: Theme.Colors.skipped
        case .minor:   Theme.Colors.primary
        }
    }
}

#Preview {
    NavigationStack { MedicineSearchView() }
        .environment(ServiceContainer.mock())
}
