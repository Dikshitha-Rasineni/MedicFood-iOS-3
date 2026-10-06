import SwiftUI

/// App entry point.
///
/// Everything the app needs is built once here and handed down through the
/// SwiftUI environment. There is no singleton service locator: a screen gets
/// what it needs because a parent gave it, which is what makes the ViewModels
/// testable.
@main
struct MedicFoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The one composition root. Which stack it builds is decided by
    /// `AppConfig.backend` — flip that to `.live` for the real Firebase
    /// backend, leave it `.mock` to demo on sample data.
    @State private var services = ServiceContainer.current()

    @State private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .environment(services)
                .environment(session)
        }
    }
}

/// Decides what the user sees based on session state.
///
/// This replaces the Flutter `SplashScreen` routing logic, which read two
/// `SharedPreferences` flags and pushed a route. Here the state drives the
/// view directly, so there is no navigation stack to get out of sync.
struct RootView: View {
    @Environment(UserSession.self) private var session

    /// The tour runs before the first sign-in, so the notification prompt
    /// arrives with some context rather than cold.
    @AppStorage("medicfood.hasSeenFeatureTour") private var hasSeenTour = false

    /// The splash owns its own dismissal.
    ///
    /// `session.restore()` finishes in about 600ms, so switching on
    /// `session.state` alone tore the splash down long before it had finished
    /// loading — and made its minimum hold dead code. The splash now reports
    /// when it is done and this waits for that.
    @State private var splashFinished = false

    var body: some View {
        Group {
            if !splashFinished {
                SplashView { splashFinished = true }
            } else {
                switch session.state {
                case .loading:
                    SplashView { splashFinished = true }
                case .signedOut:
                    if hasSeenTour {
                        SignInView()
                    } else {
                        FeatureTourView()
                    }
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: splashFinished)
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}
