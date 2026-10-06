import SwiftUI

/// Height of the colored header bar's content row, matching the visual
/// weight of the Android reference's app bar. SwiftUI automatically places
/// this below the status bar since we do NOT call ignoresSafeArea on it.
fileprivate let headerBarHeight: CGFloat = 52


struct DrugFoodInteractionView: View {

    @Environment(ServiceContainer.self) private var services
    @State private var viewModel: DrugFoodInteractionViewModel?

    var body: some View {

        let model = viewModel ?? DrugFoodInteractionViewModel(services: services)

        ZStack {
            Theme.Colors.page
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Green Header Banner
                HStack(alignment: .center) {

                    Text("Drug-Food Interactions")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer()

                    Button {
                        Task {
                            await model.loadCatalogue()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: headerBarHeight)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Theme.Colors.primary,
                            Theme.Colors.primary.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // MARK: - Search Bar
                HStack(spacing: 12) {

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    TextField(
                        "Search drugs, foods, or interactions...",
                        text: Binding(
                            get: { model.query },
                            set: { model.query = $0 }
                        )
                    )
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task {
                            await model.search()
                        }
                    }

                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
                .background(
                    Theme.Colors.cardSurface,
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                .padding(.horizontal, Theme.Metrics.pageMargin)
                .padding(.top, 14)
                .padding(.bottom, 8)

                // MARK: - Content
                if model.isSearching {

                    Spacer()
                    ProgressView()
                        .tint(Theme.Colors.primary)
                    Spacer()

                } else if model.isEmpty {

                    Spacer()

                    VStack(spacing: 14) {

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.Colors.primary)

                        Text("No medicine found")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Try searching by the generic medicine name.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                } else {

                    ScrollView(showsIndicators: false) {

                        LazyVStack(alignment: .leading, spacing: 14) {

                            Text(
                                model.query.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? "Medicines"
                                    : "Search Results"
                            )
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.top, 8)

                            ForEach(model.results) { drug in

                                NavigationLink {
                                    DrugFoodDetailView(drug: drug, model: model)
                                } label: {
                                    DrugInteractionDashboardCard(drug: drug, model: model)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Metrics.pageMargin)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            viewModel = model
            await model.loadCatalogue()
        }
    }
}


// MARK: - Dashboard Interaction Summary Row

private struct FoodInteractionSummaryRow: View {

    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}


// MARK: - Dashboard Medication Card

private struct DrugInteractionDashboardCard: View {

    let drug: DrugInfo
    let model: DrugFoodInteractionViewModel

    private var topInteraction: FoodInteraction? {
        model.topInteraction(for: drug)
    }

    private var severityTint: Color {
        switch topInteraction?.severity {
        case .avoid:   return .red
        case .caution: return .orange
        case .minor:   return Theme.Colors.primary
        case nil:      return Theme.Colors.primary
        }
    }

    private var avoidLineText: String? {
        guard let interaction = topInteraction else { return nil }

        let prefix: String
        switch interaction.severity {
        case .avoid:   prefix = "Avoid"
        case .caution: prefix = "Take care"
        case .minor:   prefix = "Note"
        }

        return "\(prefix): \(interaction.food)"
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            // MARK: Top Row
            HStack(alignment: .top, spacing: 14) {

                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.Colors.primary.opacity(0.10))

                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {

                    Text(drug.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    if let purpose = drug.purpose, !purpose.isEmpty {
                        Text(purpose)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let synonym = drug.synonym, !synonym.isEmpty {
                        Text(synonym)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 5)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.65))
            }

            // MARK: Interaction Summary
            let hasGuidance = (drug.dosageGuidance?.isEmpty == false)

            if avoidLineText != nil || hasGuidance {

                VStack(alignment: .leading, spacing: 6) {

                    if let avoidLineText {
                        FoodInteractionSummaryRow(
                            symbol: "fork.knife",
                            text: avoidLineText,
                            tint: severityTint
                        )
                    }

                    if let guidance = drug.dosageGuidance, !guidance.isEmpty {
                        FoodInteractionSummaryRow(
                            symbol: "clock",
                            text: guidance,
                            tint: Theme.Colors.primary
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.cardSurface,
                    Theme.Colors.primary.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.Colors.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .task {
            await model.loadInteractionSummary(for: drug)
        }
    }
}


// MARK: - Detail Screen

private struct DrugFoodDetailView: View {

    let drug: DrugInfo
    let model: DrugFoodInteractionViewModel

    @Environment(\.dismiss) private var dismiss

    /// "Food to Avoid" groups anything the drug flags as avoid or caution —
    /// both are things the user should be careful with.
    private var avoidInteractions: [FoodInteraction] {
        model.interactions
            .filter { $0.severity == .avoid || $0.severity == .caution }
            .sorted { $0.severity.order < $1.severity.order }
    }

    /// "Food to Take" surfaces anything flagged as generally fine.
    private var takeInteractions: [FoodInteraction] {
        model.interactions.filter { $0.severity == .minor }
    }

    var body: some View {

        ZStack {
            Theme.Colors.page
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Green Header
                HStack(spacing: 14) {

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(drug.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: headerBarHeight)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Theme.Colors.primary,
                            Theme.Colors.primary.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                ScrollView(showsIndicators: false) {

                    VStack(alignment: .leading, spacing: 20) {

                        if let synonym = drug.synonym, !synonym.isEmpty {
                            Text(synonym)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.primary)
                        }

                        // MARK: - When To Take
                        if let guidance = drug.dosageGuidance, !guidance.isEmpty {
                            AndroidStyleInfoCard(
                                title: "When to Take",
                                text: guidance,
                                symbol: "clock"
                            )
                        }

                        // MARK: - Description
                        if let purpose = drug.purpose, !purpose.isEmpty {
                            AndroidStyleInfoCard(
                                title: "Description",
                                text: purpose,
                                symbol: "cross.case"
                            )
                        }

                        // MARK: - Warnings
                        if let warnings = drug.warnings, !warnings.isEmpty {
                            AndroidStyleInfoCard(
                                title: "Warnings",
                                text: warnings,
                                symbol: "exclamationmark.triangle"
                            )
                        }

                        // MARK: - Loading
                        if model.isLoadingInteractions {

                            ProgressView()
                                .tint(Theme.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)

                        } else {

                            // MARK: - Food to Avoid
                            VStack(alignment: .leading, spacing: 12) {

                                Text("Food to Avoid")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.red)

                                if avoidInteractions.isEmpty {
                                    Text("Nothing specific")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                } else {
                                    ForEach(avoidInteractions) { interaction in
                                        FoodInteractionDetailCard(interaction: interaction)
                                    }
                                }

                                FoodImageSection(title: "Food to Avoid Image")
                            }

                            // MARK: - Food to Take
                            VStack(alignment: .leading, spacing: 12) {

                                Text("Food to Take")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Theme.Colors.primary)

                                if takeInteractions.isEmpty {
                                    Text("Nothing specific")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                } else {
                                    ForEach(takeInteractions) { interaction in
                                        FoodInteractionDetailCard(interaction: interaction)
                                    }
                                }

                                FoodImageSection(title: "Food to Take Image")
                            }
                        }

                        // MARK: - Disclaimer
                        Text("General information only. Always follow your doctor or pharmacist.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.top, 2)
                    }
                    .padding(Theme.Metrics.pageMargin)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await model.loadInteractions(for: drug)
        }
    }
}


// MARK: - Information Card

private struct AndroidStyleInfoCard: View {

    let title: String
    let text: String
    let symbol: String

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.primary)

            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.cardSurface,
                    Theme.Colors.primary.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}


// MARK: - Food Interaction Detail Card

private struct FoodInteractionDetailCard: View {

    let interaction: FoodInteraction

    private var accent: Color {
        switch interaction.severity {
        case .avoid:   return .red
        case .caution: return .orange
        case .minor:   return Theme.Colors.primary
        }
    }

    private var title: String {
        switch interaction.severity {
        case .avoid:   return "Food to Avoid"
        case .caution: return "Food to Take Care With"
        case .minor:   return "Generally Fine"
        }
    }

    var body: some View {

        HStack(spacing: 0) {

            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)

                Text(interaction.food)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(interaction.effect)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)

            Spacer(minLength: 0)
        }
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
    }
}


// MARK: - Food Image Section

private struct FoodImageSection: View {

    let title: String

    var body: some View {

        VStack(spacing: 10) {

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.primary)

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.Colors.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.Colors.primary.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

                FoodImageView(size: 64)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
        }
    }
}


#Preview {

    NavigationStack {
        DrugFoodInteractionView()
    }
    .environment(ServiceContainer.mock())
}
