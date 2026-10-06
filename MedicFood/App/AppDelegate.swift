import UIKit
import UserNotifications
import FirebaseCore

/// Application lifecycle hooks.
///
/// SwiftUI does not need an `AppDelegate` for most things, but two features
/// still do: notification delegate callbacks (tapping a reminder while the app
/// is backgrounded) and Firebase configuration.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before anything else: every Firebase call made during launch needs
        // the default app to exist already. Guarded because the config file is
        // gitignored, so a teammate's fresh clone genuinely may not have it —
        // and crashing on launch would tell them nothing useful.
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        } else if AppConfig.backend == .live {
            assertionFailure(
                "AppConfig.backend is .live but GoogleService-Info.plist is missing. "
                + "Download it from the Firebase console for project medicfood-84cbf "
                + "and put it in MedicFood/ — it is gitignored, so a pull will not bring it."
            )
        }

        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }
}

/// Receives notification taps and forwards the chosen action.
///
/// Kept deliberately thin: it does not touch adherence or medicine state
/// directly. It hands the action to `NotificationActionRouter`, which is the
/// single place that knows what "Taken" means.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Set by `MainTabView` on appear, so a tap can reach the live services.
    var router: NotificationActionRouter?

    /// Show reminders even when the app is in the foreground — a medication
    /// reminder the user misses because they happened to have the app open is
    /// a real failure.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // With the app open, show the full in-app alert instead of a banner.
        if router != nil,
           let doseID = notification.request.content.userInfo["doseID"] as? String {
            await MainActor.run { ReminderPresenter.shared.show(doseID: doseID) }
            return [.sound, .list]
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // When a button is tapped on a launch from a terminated app, the
        // services are not up yet. Wait briefly rather than dropping the dose.
        var attempts = 0
        while router == nil && attempts < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        await router?.handle(response: response)
    }
}
