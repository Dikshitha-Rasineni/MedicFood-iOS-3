import SwiftUI

/// A destination that is deliberately not built yet.
///
/// Better than routing to a half-finished screen or a dead button: it says
/// plainly that the feature is planned, so a reviewer does not report it as a
/// bug and a teammate knows the slot is theirs to fill.
struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "hammer")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 88, height: 88)
                .background(Theme.Colors.surface, in: Circle())

            Spacer().frame(height: 24)

            Text(title)
                .font(Theme.Typography.screenTitle)
                .tracking(Theme.Typography.screenTitleTracking)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer().frame(height: 8)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(title: "Drug-Food Interactions", message: "This screen is not built yet.")
    }
}
