import SwiftUI

/// The signed-out half of the app: sign in, create an account, or look around
/// the demo.
///
/// A `NavigationStack` rather than a mode flag on one screen. Creating an
/// account asks for different things than signing in, and pushing gives the
/// move a direction — forwards into a new task, back out of it — which a
/// cross-fade between two states of the same form does not.
struct AuthFlowView: View {

    enum Route: Hashable { case signUp }

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            SignInView(onCreateAccount: { path.append(.signUp) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .signUp:
                        SignUpView(onSignedUp: { path.removeAll() })
                    }
                }
        }
        .tint(Theme.Colors.primary)
    }
}

// MARK: - Shared chrome

/// The logo, wordmark and tagline that both auth screens open with.
///
/// Shared so the two screens line up to the pixel: pushing from one to the
/// other should look like the content beneath the mark changed, not like the
/// whole page was rebuilt.
struct AuthHeader: View {
    var title: String
    var subtitle: String

    /// Drives the entrance. Starts false and is set on appear.
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .scaleEffect(shown ? 1 : 0.86)
                .opacity(shown ? 1 : 0)

            Text(title)
                .font(Theme.Typography.screenTitle)
                .tracking(Theme.Typography.screenTitleTracking)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
        .onAppear {
            withAnimation(Theme.Motion.cardAppear) { shown = true }
        }
    }
}

/// Fades and lifts its content in, a beat after the one above it.
///
/// The stagger is what makes the form feel like it is arriving rather than
/// being switched on. Kept small — 45ms a row — so it reads as responsive, not
/// as a loading sequence.
struct StaggeredAppear<Content: View>: View {
    var index: Int
    @ViewBuilder var content: Content

    @State private var shown = false

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(Theme.Motion.cardAppear.delay(Double(index) * 0.045)) {
                    shown = true
                }
            }
    }
}

/// The filled primary action, with its own in-place loading state.
///
/// The spinner replaces the label inside the same pill rather than swapping
/// the button for a different control, so nothing moves while a request is in
/// flight and the button cannot be pressed twice.
struct AuthSubmitButton: View {
    var title: String
    var isLoading: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(isLoading ? 0 : 1)

                ProgressView()
                    .tint(.white)
                    .opacity(isLoading ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                    // Filled buttons must use `primary`: `brand` is 2.78:1 on
                    // white and fails AA. See Theme.
                    .fill(Theme.Colors.primary)
                    .opacity(isEnabled ? 1 : 0.4)
            )
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!isEnabled || isLoading)
        .animation(Theme.Motion.statusChange, value: isLoading)
        .animation(Theme.Motion.statusChange, value: isEnabled)
    }
}
