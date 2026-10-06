import UIKit
import UserNotifications

/// Application lifecycle hooks.
///
/// SwiftUI does not need an `AppDelegate` for most things, but two features
/// still do: notification delegate callbacks (tapping a reminder while the app
/// is backgrounded) and, later, Firebase configuration.
///
/// When Firebase is wired up, `FirebaseApp.configure()` goes in
/// `didFinishLaunchingWithOptions` — before anything else runs.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // FirebaseApp.configure()   <- add here once GoogleService-Info.plist exists
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
