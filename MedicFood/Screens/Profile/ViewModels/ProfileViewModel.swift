import Foundation
import Observation
import UserNotifications

/// Drives the profile screen: who is signed in, notification state, and the
/// caretaker share code.
@MainActor
@Observable
final class ProfileViewModel {

    private(set) var notificationsAuthorized = false
    private(set) var pendingReminderCount = 0
    private(set) var isWorking = false

    private let auth: AuthServicing
    private let notifications: NotificationScheduling

    init(auth: AuthServicing, notifications: NotificationScheduling) {
        self.auth = auth
        self.notifications = notifications
    }

    convenience init(services: ServiceContainer) {
        self.init(auth: services.auth, notifications: services.notifications)
    }

    /// Shown on the notifications row.
    ///
    /// The pending count is worth surfacing because of the iOS 64-notification
    /// cap: if it ever reads at or above the window size, reminders are being
    /// dropped and this is the only place that would show it.
    var notificationSummary: String {
        guard notificationsAuthorized else { return "Off — reminders will not appear" }
        return "\(pendingReminderCount) reminder\(pendingReminderCount == 1 ? "" : "s") scheduled"
    }

    var isNearNotificationLimit: Bool {
        pendingReminderCount >= NotificationService.windowSize
    }

    func refresh() async {
        notificationsAuthorized = await notifications.authorizationStatus() == .authorized
        pendingReminderCount = await notifications.pendingCount()
    }

    func requestNotificationAccess() async {
        isWorking = true
        defer { isWorking = false }
        notificationsAuthorized = await notifications.requestAuthorization()
        await refresh()
    }

    /// Signs out and cancels every scheduled reminder.
    ///
    /// Cancelling matters: without it the previous user's reminders keep
    /// firing on a shared device.
    func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await notifications.cancelAll()
        try? await auth.signOut()
    }
}
