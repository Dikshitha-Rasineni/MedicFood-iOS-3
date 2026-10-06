import SwiftUI

/// Photograph a medicine pack to find out what it is, and what to eat or avoid
/// with it.
struct IdentifyMedicineView: View {
    @Environment(ServiceContainer.self) private var services
    @State private var model: IdentifyMedicineViewModel?

    var body: some View {
        Group {
            if let model {
                IdentifyContent(model: model)
            } else {
                Theme.Colors.page.ignoresSafeArea()
            }
        }
        .onAppear {
            if model == nil { model = IdentifyMedicineViewModel(services: services) }
        }
    }
}

private struct IdentifyContent: View {
    @Bindable var model: IdentifyMedicineViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Identify a medicine")
                    .font(Theme.Typography.screenTitle)
                    .tracking(Theme.Typography.screenTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, 8)

                Text("Photograph the front of the pack, strip or bottle, with the name facing the camera.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Card {
                    MedicineImageSlot(title: "Medicine pack", image: $model.image)
                }

                identifyButton

                if let notice = model.aiNotice {
                    NoticeCard(symbol: "info.circle.fill", text: notice, tint: Theme.Colors.skipped)
                }

                switch model.phase {
                case .idle:
                    EmptyView()
                case .reading(let message):
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.Colors.primary)
                        Text(message)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, 8)
                case .failed(let message):
                    ErrorBanner(message: message)
                case .found(let result):
                    found(result)
                }
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.bottom, 32)
            .animation(Theme.Motion.cardAppear, value: model.phase)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .aiConsentAlert(model.consent)
    }

    // MARK: - Button

    private var identifyButton: some View {
        AuthSubmitButton(
            title: "Identify",
            isLoading: model.isReading,
            isEnabled: model.canIdentify
        ) {
            Task { await model.identify() }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func found(_ result: IdentifyMedicineViewModel.Result) -> some View {
        let found = result.identification

        header(found, source: result.source)

        if let purpose = found.purpose {
            SettingsSection(
                title: "What it is for",
                footer: "Written by AI from the name on the pack. General information only."
            ) {
                Text(purpose)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }

        SettingsSection(
            title: "Food and drink",
            footer: "From MedicFood's medicines database. General information only. Always follow your doctor or pharmacist."
        ) {
            foodContent
        }

        if let prefill = model.prefill() {
            NavigationLink {
                AddMedicineView(prefill: prefill, isModal: false)
            } label: {
                Label("Add to my medicines", systemImage: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                            .fill(Theme.Colors.surface)
                    )
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private func header(_ found: MedicineIdentification, source: IdentifyMedicineViewModel.Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(found.name)
                .font(Theme.Typography.screenTitle)
                .tracking(Theme.Typography.screenTitleTracking)
                .foregroundStyle(.white)

            if let generic = found.genericName {
                Text(generic)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 8) {
                if let strength = found.strength { chip(strength) }
                if let form = found.form { chip(form.displayName) }
            }

            Label(
                source == .gemini ? "Read with Gemini AI" : "Read on this device",
                systemImage: source == .gemini ? "sparkles" : "iphone"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.Colors.primary, Theme.Colors.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white, in: Capsule())
    }

    // MARK: - Food

    @ViewBuilder
    private var foodContent: some View {
        switch model.food.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.Colors.primary)
                Text("Checking food interactions...")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(14)

        case .found(let interactions, _):
            ForEach(Array(interactions.enumerated()), id: \.element.id) { index, interaction in
                if index > 0 { SettingsDivider(inset: 14) }
                FoodInteractionRow(interaction: interaction)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }

        case .none(let searched):
            Label("No food interactions recorded for \"\(searched)\".", systemImage: "checkmark.circle")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(14)

        case .failed(let message):
            // Never shown as "nothing to avoid": a failed lookup is not a clear one.
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.missed)
                .padding(14)
        }
    }
}

#Preview {
    NavigationStack { IdentifyMedicineView() }
        .environment(ServiceContainer.mock())
}
