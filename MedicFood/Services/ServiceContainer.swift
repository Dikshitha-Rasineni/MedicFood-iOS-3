import Foundation
import Observation
import UserNotifications

/// The composition root: every service the app uses, built in one place.
///
/// This is what makes the protocol seam pay off. Screens ask the environment
/// for the container, never for a concrete service, so swapping the mock stack
/// for a Firebase one is a single edit here — and a test can build its own
/// container with fakes and drive a ViewModel with no network, no database and
/// no simulator.
///
/// It replaces the Flutter app's singleton pattern (`factory` + a static
/// instance on each service), where every screen reached out and grabbed
/// whatever it wanted and nothing could be substituted.
@MainActor
@Observable
final class ServiceContainer {

    let auth: AuthServicing
    let medicines: MedicineServicing
    let adherence: AdherenceServicing
    let notifications: NotificationScheduling
    let drugInfo: DrugInfoServicing
    let caretakers: CaretakerServicing

    init(
        auth: AuthServicing,
        medicines: MedicineServicing,
        adherence: AdherenceServicing,
        notifications: NotificationScheduling,
        drugInfo: DrugInfoServicing,
        caretakers: CaretakerServicing
    ) {
        self.auth = auth
        self.medicines = medicines
        self.adherence = adherence
        self.notifications = notifications
        self.drugInfo = drugInfo
        self.caretakers = caretakers
    }

    /// Runs entirely on-device with seeded data. No backend, no secrets, no
    /// `GoogleService-Info.plist` — the app builds and runs from a fresh
    /// clone.
    static func mock() -> ServiceContainer {
        ServiceContainer(
            auth: MockAuthService(),
            medicines: MockMedicineService(),
            adherence: MockAdherenceService(),
            notifications: NotificationService(),
            drugInfo: MockDrugInfoService(),
            caretakers: MockCaretakerService()
        )
    }

    /// The real stack: Firebase project `medicfood-84cbf`, the same backend the
    /// Android app uses, so data written on either platform appears on both.
    ///
    /// Needs `GoogleService-Info.plist` in `MedicFood/`. It is gitignored, so a
    /// fresh clone does not have it — see the README.
    ///
    /// `NotificationService` is shared with the mock stack on purpose:
    /// reminders are local to the device and have no backend half.
    static func live() -> ServiceContainer {
        ServiceContainer(
            auth: FirebaseAuthService(),
            medicines: FirestoreMedicineService(),
            adherence: FirestoreAdherenceService(),
            notifications: NotificationService(),
            drugInfo: FirestoreDrugInfoService(),
            caretakers: FirestoreCaretakerService()
        )
    }

    /// Whichever stack `AppConfig.backend` selects.
    ///
    /// One switch, in one file, so running a demo on sample data is a one-line
    /// change rather than an edit spread across the app.
    static func current() -> ServiceContainer {
        switch AppConfig.backend {
        case .mock: mock()
        case .live: live()
        }
    }
}

/// Turns a notification button tap into the right call.
///
/// One place decides what "Taken" means, so the live path and the
/// tapped-while-terminated path cannot drift apart — they did in the Flutter
/// app, where the snooze guard had to be duplicated in both and was a
/// recurring source of corrupted adherence data.
@MainActor
final class NotificationActionRouter {

    private let services: ServiceContainer

    init(services: ServiceContainer) {
        self.services = services
    }

    func handle(response: UNNotificationResponse) async {
        guard let doseID = response.notification.request.content.userInfo["doseID"] as? String else { return }

        // Tapping the notification body (not a button) opens the in-app alert.
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            ReminderPresenter.shared.show(doseID: doseID)
            return
        }
        guard let action = DoseAction(rawValue: response.actionIdentifier) else { return }

        // Snooze reschedules and returns. It never reaches the adherence log,
        // which is guaranteed by `DoseAction.outcome` returning nil rather
        // than by a runtime check that someone can forget.
        guard let outcome = action.outcome else {
            if action == .snooze, let dose = try? await dose(withID: doseID) {
                await services.notifications.snooze(dose, byMinutes: NotificationService.snoozeMinutes)
            }
            return
        }

        guard let dose = try? await dose(withID: doseID) else { return }
        try? await services.adherence.record(outcome, for: dose)
        await services.notifications.cancel(doseID: doseID)
    }

    /// Rebuild the dose a notification refers to. Dose ids encode the day, so
    /// this is a lookup rather than stored state.
    func dose(withID id: String) async throws -> Dose? {
        for offset in -1...1 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) else { continue }
            let doses = try await services.medicines.doses(on: day)
            if let match = doses.first(where: { $0.id == id }) { return match }
        }
        return nil
    }
}
