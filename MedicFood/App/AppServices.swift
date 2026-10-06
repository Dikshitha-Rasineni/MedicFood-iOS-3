import Foundation
import Observation

/// Owns the service stack the app is currently running on, and lets it be
/// swapped at runtime.
///
/// `AppConfig.backend` decides what the app *starts* on. Demo mode is the one
/// thing that changes it afterwards: tapping "Explore the demo" has to swap in
/// the mock stack, because signing in a demo profile while the Firestore
/// services are live would put a signed-in user in front of an app where every
/// read fails with `.notSignedIn`.
///
/// Views keep reading `ServiceContainer` from the environment and know nothing
/// about this — replacing the container re-renders them with the new one.
@MainActor
@Observable
final class AppServices {

    private(set) var container: ServiceContainer

    /// True when the app is showing sample data rather than a real account —
    /// either because `AppConfig.backend` is `.mock`, or because the user
    /// chose the demo at sign-in.
    private(set) var isDemo: Bool

    init() {
        container = ServiceContainer.current()
        isDemo = AppConfig.backend == .mock
    }

    /// Swap to sample data and hand back the profile to sign in with.
    ///
    /// The demo profile is deliberately *not* persisted by `UserSession`, so a
    /// relaunch returns to the sign-in screen rather than silently leaving
    /// someone in a demo they have forgotten they entered.
    func enterDemo() -> UserProfile {
        container = ServiceContainer.mock()
        isDemo = true
        return Self.demoProfile
    }

    /// Back to whatever `AppConfig.backend` selects. Called on sign-out, so
    /// leaving the demo does not require relaunching the app.
    func leaveDemo() {
        container = ServiceContainer.current()
        isDemo = AppConfig.backend == .mock
    }

    static let demoProfile = UserProfile(
        id: "demo-user",
        name: "Demo",
        email: "demo@medicfood.app",
        shareCode: "DEMO01"
    )
}
