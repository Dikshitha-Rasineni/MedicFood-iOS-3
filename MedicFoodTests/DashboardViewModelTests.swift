import XCTest
import UserNotifications
@testable import MedicFood

/// Drives a ViewModel with no UI, no network and no simulator.
///
/// This is the payoff from the MVVM split and the protocol seam: the whole
/// dashboard behaviour is testable because `DashboardViewModel` takes services
/// as protocols and imports no SwiftUI. None of this was possible in the
/// Flutter version, where the same logic lived inside a 4,557-line widget.
@MainActor
final class DashboardViewModelTests: XCTestCase {

    /// Isolated defaults per test, so the mocks do not persist between runs.
    private func makeServices() -> (DashboardViewModel, MockAdherenceService) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let medicines = MockMedicineService(defaults: defaults, seeded: false)
        let adherence = MockAdherenceService(defaults: defaults)
        let notifications = StubNotificationService()

        let model = DashboardViewModel(
            medicines: medicines,
            adherence: adherence,
            notifications: notifications
        )
        self.medicineService = medicines
        return (model, adherence)
    }

    private var medicineService: MockMedicineService!

    func testTwiceDailyMedicineProducesTwoDoses() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(name: "Amoxicillin", dosage: "500 mg", slots: [.morning, .night], durationDays: 7)
        )

        await model.load()

        XCTAssertEqual(model.totalCount, 2)
        XCTAssertEqual(model.groupedBySlot.count, 2)
    }

    func testDosesAreGroupedAndOrderedByTimeOfDay() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(name: "Metformin", dosage: "850 mg", slots: [.night, .morning, .afternoon], durationDays: 7)
        )

        await model.load()

        XCTAssertEqual(model.groupedBySlot.map(\.slot), [.morning, .afternoon, .night])
    }

    func testRecordingTakenUpdatesProgress() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(name: "Vitamin D3", dosage: "1", slots: [.morning, .night], durationDays: 7)
        )
        await model.load()

        XCTAssertEqual(model.progress, 0)

        let first = try XCTUnwrap(model.items.first)
        await model.record(.taken, for: first)

        XCTAssertEqual(model.takenCount, 1)
        XCTAssertEqual(model.progress, 0.5)
    }

    func testSkippingDoesNotCountAsTaken() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(name: "Aspirin", dosage: "75 mg", slots: [.morning], durationDays: 7)
        )
        await model.load()

        let dose = try XCTUnwrap(model.items.first)
        await model.record(.skipped, for: dose)

        XCTAssertEqual(model.takenCount, 0)
        XCTAssertTrue(model.items[0].isActioned)
    }

    func testOutcomeSurvivesAReload() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(name: "Aspirin", dosage: "75 mg", slots: [.morning], durationDays: 7)
        )
        await model.load()

        await model.record(.taken, for: try XCTUnwrap(model.items.first))
        await model.load()

        XCTAssertEqual(model.items.first?.outcome, .taken)
    }

    func testFinishedCourseProducesNoDoses() async throws {
        let (model, _) = makeServices()
        try await medicineService.save(
            Medicine(
                name: "Old course",
                dosage: "1",
                slots: [.morning],
                startDate: Date.now.startOfDay.adding(days: -30),
                durationDays: 7
            )
        )

        await model.load()

        XCTAssertTrue(model.isEmpty, "A course that ended 23 days ago must not still remind")
    }

    func testEmptyDashboardReportsEmpty() async {
        let (model, _) = makeServices()
        await model.load()
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.progress, 0)
    }
}

/// Records what it was asked to do, so tests can assert on scheduling without
/// touching `UNUserNotificationCenter`.
@MainActor
final class StubNotificationService: NotificationScheduling {
    private(set) var scheduled: [Dose] = []
    private(set) var cancelled: [String] = []
    private(set) var snoozed: [(Dose, Int)] = []

    func requestAuthorization() async -> Bool { true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func schedule(_ doses: [Dose]) async { scheduled = doses }
    func cancel(doseID: String) async { cancelled.append(doseID) }
    func cancelAll() async { scheduled.removeAll() }
    func snooze(_ dose: Dose, byMinutes minutes: Int) async { snoozed.append((dose, minutes)) }
    func pendingCount() async -> Int { scheduled.count }
}
