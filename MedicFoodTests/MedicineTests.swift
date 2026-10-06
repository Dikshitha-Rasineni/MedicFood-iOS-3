import XCTest
@testable import MedicFood

/// Tests for the typed `Medicine` model — the thing the Flutter codebase never
/// had, where medicines travelled as `Map<String, dynamic>` through 31,000
/// lines with no compiler checking.
final class MedicineTests: XCTestCase {

    private let today = Calendar.current.startOfDay(for: .now)

    private func medicine(startOffset: Int = 0, duration: Int?) -> Medicine {
        Medicine(
            name: "Test",
            dosage: "1 tablet",
            slots: [.morning, .night],
            startDate: today.adding(days: startOffset),
            durationDays: duration
        )
    }

    func testFixedCourseEndsOnTheRightDay() {
        // A 7-day course starting today runs today + 6 more days.
        let medicine = medicine(duration: 7)
        XCTAssertEqual(medicine.endDate, today.adding(days: 6))
    }

    func testOneDayCourseEndsSameDay() {
        XCTAssertEqual(medicine(duration: 1).endDate, today)
    }

    func testIndefiniteCourseHasNoEndDate() {
        XCTAssertNil(medicine(duration: nil).endDate)
    }

    func testScheduledWithinTheCourse() {
        let medicine = medicine(duration: 7)
        XCTAssertTrue(medicine.isScheduled(on: today))
        XCTAssertTrue(medicine.isScheduled(on: today.adding(days: 6)))
    }

    func testNotScheduledAfterTheCourseEnds() {
        let medicine = medicine(duration: 7)
        XCTAssertFalse(
            medicine.isScheduled(on: today.adding(days: 7)),
            "Reminders must stop when the course finishes"
        )
    }

    func testNotScheduledBeforeItStarts() {
        let medicine = medicine(startOffset: 3, duration: 7)
        XCTAssertFalse(medicine.isScheduled(on: today))
        XCTAssertTrue(medicine.isScheduled(on: today.adding(days: 3)))
    }

    func testIndefiniteCourseIsAlwaysScheduled() {
        let medicine = medicine(duration: nil)
        XCTAssertTrue(medicine.isScheduled(on: today.adding(days: 500)))
    }

    func testInactiveMedicineIsNeverScheduled() {
        var medicine = medicine(duration: 7)
        medicine.isActive = false
        XCTAssertFalse(medicine.isScheduled(on: today))
    }

    func testFrequencyDescriptionFollowsSlotCount() {
        XCTAssertEqual(Medicine(name: "a", dosage: "1", slots: [.morning]).frequencyDescription, "Once daily")
        XCTAssertEqual(Medicine(name: "a", dosage: "1", slots: [.morning, .night]).frequencyDescription, "Twice daily")
        XCTAssertEqual(
            Medicine(name: "a", dosage: "1", slots: [.morning, .afternoon, .night]).frequencyDescription,
            "Three times daily"
        )
    }

    func testMedicineRoundTripsThroughJSON() throws {
        let original = medicine(duration: 14)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Medicine.self, from: data)
        XCTAssertEqual(original, restored)
    }
}

/// The dose id is used as the notification identifier. If it stops being
/// stable, every reminder already scheduled on every installed device is
/// orphaned — so it is pinned here.
final class DoseTests: XCTestCase {

    func testDoseIDIsStableForTheSameMedicineDayAndSlot() {
        let medicine = Medicine(name: "Test", dosage: "1", slots: [.morning])
        let day = Calendar.current.startOfDay(for: .now)

        let first = Dose(medicine: medicine, slot: .morning, day: day)
        let second = Dose(medicine: medicine, slot: .morning, day: day)

        XCTAssertEqual(first.id, second.id)
    }

    func testDoseIDDiffersBySlot() {
        let medicine = Medicine(name: "Test", dosage: "1", slots: [.morning, .night])
        let day = Calendar.current.startOfDay(for: .now)

        XCTAssertNotEqual(
            Dose(medicine: medicine, slot: .morning, day: day).id,
            Dose(medicine: medicine, slot: .night, day: day).id
        )
    }

    func testScheduledAtUsesTheSlotTime() {
        let medicine = Medicine(name: "Test", dosage: "1", slots: [.morning])
        let dose = Dose(medicine: medicine, slot: .morning, day: .now)

        let hour = Calendar.current.component(.hour, from: dose.scheduledAt)
        XCTAssertEqual(hour, 8, "Morning doses are scheduled for 08:00")
    }

    /// Snooze must not be expressible as an adherence outcome. This is the bug
    /// the Flutter code kept re-introducing, guarded there by three separate
    /// runtime checks; here the type system prevents it.
    func testSnoozeProducesNoAdherenceOutcome() {
        XCTAssertNil(DoseAction.snooze.outcome)
        XCTAssertEqual(DoseAction.taken.outcome, .taken)
        XCTAssertEqual(DoseAction.skipped.outcome, .skipped)
    }

    func testOnlyTakenCountsTowardAdherence() {
        XCTAssertTrue(DoseOutcome.taken.countsAsAdherent)
        XCTAssertFalse(DoseOutcome.skipped.countsAsAdherent)
        XCTAssertFalse(DoseOutcome.missed.countsAsAdherent)
    }

    func testEmptyPeriodReportsFullAdherenceNotZero() {
        // A new user should not be shown "0%" before taking anything.
        XCTAssertEqual(AdherenceStats().percentage, 100)
    }
}
