import Foundation
import UserNotifications

/// Scheduling and cancelling dose reminders.
@MainActor
protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Register reminders for these doses, respecting the iOS pending limit.
    func schedule(_ doses: [Dose]) async
    func cancel(doseID: String) async
    func cancelAll() async

    /// Push a dose's reminder back by `minutes`.
    ///
    /// Snoozing is here, and deliberately *not* on `AdherenceServicing` —
    /// a snooze must never reach the adherence log.
    func snooze(_ dose: Dose, byMinutes minutes: Int) async

    func pendingCount() async -> Int

    /// Fire a real reminder for `medicine` after a few seconds, so the
    /// notification, sound and action buttons can be checked by hand.
    func scheduleTest(for medicine: Medicine, afterSeconds seconds: Int) async
}

extension NotificationScheduling {
    func scheduleTest(for medicine: Medicine, afterSeconds seconds: Int) async {}
}

/// Re-registers reminders for the days ahead from the stored medicines.
@MainActor
enum ReminderScheduler {
    static func refresh(
        medicines: MedicineServicing,
        notifications: NotificationScheduling,
        days: Int = 14
    ) async {
        var upcoming: [Dose] = []
        for offset in 0..<days {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: .now),
                  let doses = try? await medicines.doses(on: day) else { continue }
            upcoming.append(contentsOf: doses.filter { $0.medicine.isReminderOn })
        }
        await notifications.schedule(upcoming)
    }
}

/// Real reminders, via `UNUserNotificationCenter`.
///
/// ## The 64-notification cap
///
/// iOS allows at most **64 pending local notifications per app** and silently
/// drops everything past that. A realistic prescription — 4 medicines × 3
/// doses × 30 days — is 360 reminders, so naively scheduling the whole course
/// means the app appears to work and then stops reminding people to take
/// medication. For a health app that is the worst possible failure mode.
///
/// So this class registers only the **soonest `windowSize` doses** and tops
/// the window up whenever the app comes to the foreground. `windowSize` is
/// under the cap on purpose, leaving headroom for snoozes created at runtime.
///
/// > If you add a code path that schedules doses, call `topUpWindow()` after
/// > it, or the doses are never registered with iOS.
@MainActor
final class NotificationService: NotificationScheduling {

    /// Below the 64 limit, leaving room for runtime snoozes.
    static let windowSize = 55

    /// Default snooze length. Change here and the notification action, the
    /// router and the in-app buttons all follow.
    nonisolated static let snoozeMinutes = 10

    private let center: UNUserNotificationCenter
    /// Every dose we have been asked to remind about, soonest first.
    private var ledger: [Dose] = []

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func schedule(_ doses: [Dose]) async {
        ledger = doses
            .filter { $0.scheduledAt > .now }
            .sorted { $0.scheduledAt < $1.scheduledAt }

        // A dose id stays the same when the user changes its time, so a
        // request already pending under that id would keep the OLD time.
        // Clear pending dose reminders (not snoozes) before re-registering.
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { !Self.isRuntimeRequest($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        await topUpWindow()
    }

    /// Reconcile the ledger with what iOS actually holds: drop what has
    /// passed, register what has come into the window.
    func topUpWindow() async {
        ledger.removeAll { $0.scheduledAt <= .now }

        let window = Array(ledger.prefix(Self.windowSize))
        let wanted = Set(window.map(\.id))

        let pending = await center.pendingNotificationRequests()
        let existing = Set(pending.map(\.identifier))

        // Cancel anything that has fallen out of the window.
        // Snoozes and test reminders are created at runtime and are not part
        // of the window, so they must never be swept up as "stale".
        let stale = existing.subtracting(wanted).filter { !Self.isRuntimeRequest($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        // Register anything newly inside it.
        for dose in window where !existing.contains(dose.id) {
            await add(dose)
        }
    }

    func cancel(doseID: String) async {
        ledger.removeAll { $0.id == doseID }
        center.removePendingNotificationRequests(withIdentifiers: [doseID, "\(doseID)-snoozed"])
        await topUpWindow()
    }

    func cancelAll() async {
        ledger.removeAll()
        center.removeAllPendingNotificationRequests()
    }

    func snooze(_ dose: Dose, byMinutes minutes: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [dose.id])

        let content = content(for: dose)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        // Suffixed id so the snoozed copy does not collide with the original
        // dose, which may still be topped up into the window later.
        let request = UNNotificationRequest(
            identifier: "\(dose.id)-snoozed",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    func scheduleTest(for medicine: Medicine, afterSeconds seconds: Int) async {
        _ = await requestAuthorization()
        let dose = Dose(medicine: medicine, slot: medicine.slots.first ?? .morning, day: .now)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(seconds, 1)), repeats: false)
        let request = UNNotificationRequest(identifier: "\(dose.id)-test", content: content(for: dose), trigger: trigger)
        try? await center.add(request)
    }

    private static func isRuntimeRequest(_ id: String) -> Bool {
        id.hasSuffix("-snoozed") || id.hasSuffix("-test")
    }

    /// Notification attachments are moved by the system, so give it a copy.
    private static func attachment(forImageNamed name: String) -> UNNotificationAttachment? {
        let source = MediaStore.url(for: name)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return try UNNotificationAttachment(identifier: "medicine", url: copy, options: nil)
        } catch {
            return nil
        }
    }

    // MARK: - Building notifications

    private func add(_ dose: Dose) async {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dose.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: dose.id,
            content: content(for: dose),
            trigger: trigger
        )
        try? await center.add(request)
    }

    private func content(for dose: Dose) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time to take \(dose.medicine.name)"
        content.subtitle = "MedicFood"

        var subtitle = dose.medicine.dosage
        if dose.medicine.foodInstruction != .anyTime {
            subtitle += " · \(dose.medicine.foodInstruction.displayName.lowercased())"
        }
        content.body = subtitle

        if let name = dose.medicine.frontImagePath,
           let attachment = Self.attachment(forImageNamed: name) {
            content.attachments = [attachment]
        }

        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["doseID": dose.id]

        // Time Sensitive breaks through Focus modes without needing the
        // Critical Alerts entitlement, which Apple grants only on application.
        // This is the strongest interruption available to us today.
        content.interruptionLevel = .timeSensitive

        return content
    }

    static let categoryID = "MEDICINE_REMINDER"

    private func registerCategories() {
        let take = UNNotificationAction(
            identifier: DoseAction.taken.rawValue,
            title: "Taken",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: DoseAction.snooze.rawValue,
            title: "Snooze",
            options: []
        )
        let skip = UNNotificationAction(
            identifier: DoseAction.skipped.rawValue,
            title: "Dismissed",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [take, snooze, skip],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
}

/// The buttons on a reminder.
///
/// `snooze` sits alongside the two adherence outcomes here because that is
/// what the *notification* offers — but note it converts to `nil` in
/// `outcome`, so it cannot be written to the adherence log by accident.
enum DoseAction: String, Sendable {
    case taken = "DOSE_TAKEN"
    case skipped = "DOSE_SKIPPED"
    case snooze = "DOSE_SNOOZE"

    /// The adherence outcome this action implies, if any.
    /// Snoozing implies none — that is the whole point.
    var outcome: DoseOutcome? {
        switch self {
        case .taken:   .taken
        case .skipped: .skipped
        case .snooze:  nil
        }
    }
}
