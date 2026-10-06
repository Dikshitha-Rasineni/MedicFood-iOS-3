import XCTest
@testable import MedicFood

/// Checks this app reads and writes the documents the **Android app already
/// writes** in Firebase project `medicfood-84cbf`.
///
/// The payloads below are not invented: they are the shapes
/// `lib/services/medicine_service.dart` and `lib/services/adherence_service.dart`
/// produce, copied field for field. They are the only check available until an
/// iOS app is registered in the Firebase console, and they stay useful
/// afterwards — they fail fast if someone "tidies" a key name and quietly
/// splits the two platforms apart.
final class FirestoreSchemaTests: XCTestCase {

    // MARK: - Identity

    /// Reminders are keyed by `Dose.id`, which is built from `Medicine.id`. If
    /// the same Firestore document produced a different UUID on a later launch,
    /// every scheduled notification would be orphaned.
    func testStableUUIDIsDerivedNotGenerated() {
        let first = FirestoreSchema.stableUUID(from: "7bQv2mK1xLpR9dNfTz3A")
        let second = FirestoreSchema.stableUUID(from: "7bQv2mK1xLpR9dNfTz3A")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, FirestoreSchema.stableUUID(from: "differentDocumentId"))
    }

    func testStableUUIDIsAWellFormedVersion5UUID() {
        let uuid = FirestoreSchema.stableUUID(from: "anything")
        // Version nibble and RFC 4122 variant bits.
        XCTAssertEqual(uuid.uuid.6 >> 4, 0x5)
        XCTAssertEqual(uuid.uuid.8 >> 6, 0b10)
    }

    // MARK: - Reading a medicine written by Android

    /// Exactly what `saveMedicine` puts in the `medicines` map.
    private var androidMedicine: [String: Any] {
        [
            "id": "7bQv2mK1xLpR9dNfTz3A",
            "name": "Amoxicillin",
            "dosage": "500 mg",
            "type": "Tablet",
            "frequency": "Twice Daily",
            "timing": "Morning & Night",
            "time": "08:00 AM",
            "instructions": "Finish the full course",
            "foodInstructions": "After Food",
            "duration": "5 days",
            "scheduleDate": "2026-10-06",
            "startDate": "2026-10-06",
            "endDate": "2026-10-10",
            "isActive": true,
            "isFromPrescription": true,
            "notes": "",
            "createdAt": "2026-10-06T08:00:00.000",
            "scheduleDates": ["2026-10-06"],
            "scheduleData": [["date": "2026-10-06", "isCompleted": false, "completedAt": NSNull(), "notes": ""]],
        ]
    }

    func testReadsAndroidMedicine() throws {
        let medicine = try XCTUnwrap(
            FirestoreSchema.medicine(from: androidMedicine, remoteID: "7bQv2mK1xLpR9dNfTz3A")
        )

        XCTAssertEqual(medicine.name, "Amoxicillin")
        XCTAssertEqual(medicine.dosage, "500 mg")
        XCTAssertEqual(medicine.form, .tablet)
        XCTAssertEqual(medicine.foodInstruction, .afterFood)
        XCTAssertEqual(medicine.instructions, "Finish the full course")
        XCTAssertTrue(medicine.isActive)
        XCTAssertTrue(medicine.isFromPrescription)

        // "Morning & Night" is free-form on Android; it must land as two slots.
        XCTAssertEqual(medicine.slots.sorted(), [.morning, .night])

        // The remote key is kept so a write goes back to the same document
        // rather than creating a second one Android would render twice.
        XCTAssertEqual(medicine.remoteID, "7bQv2mK1xLpR9dNfTz3A")
        XCTAssertEqual(medicine.id, FirestoreSchema.stableUUID(from: "7bQv2mK1xLpR9dNfTz3A"))
    }

    /// `endDate` is the last day the medicine is taken, inclusive, so
    /// 6th→10th October is a five-day course rather than four.
    func testDurationPrefersExplicitDatesAndIsInclusive() throws {
        let medicine = try XCTUnwrap(FirestoreSchema.medicine(from: androidMedicine, remoteID: "x"))
        XCTAssertEqual(medicine.durationDays, 5)
    }

    /// A document with neither `startDate` nor `endDate` has to fall back to
    /// the free-text `duration`, which is what older Android writes carry.
    func testDurationFallsBackToFreeText() throws {
        var fields = androidMedicine
        fields.removeValue(forKey: "startDate")
        fields.removeValue(forKey: "endDate")
        fields["duration"] = "1 week"

        let medicine = try XCTUnwrap(FirestoreSchema.medicine(from: fields, remoteID: "x"))
        XCTAssertEqual(medicine.durationDays, 7)
    }

    /// Android reads every field as `?? 'default'`, so documents really do
    /// arrive with most keys missing. A strict decode would drop real
    /// medicines; only a missing *name* is fatal.
    func testReadsSparseDocument() throws {
        let medicine = try XCTUnwrap(
            FirestoreSchema.medicine(from: ["name": "Metformin"], remoteID: "abc")
        )
        XCTAssertEqual(medicine.name, "Metformin")
        XCTAssertEqual(medicine.form, .tablet)
        XCTAssertEqual(medicine.foodInstruction, .anyTime)
        XCTAssertFalse(medicine.slots.isEmpty, "A medicine with no slots is never reminded about")
        XCTAssertNil(medicine.durationDays, "No duration means ongoing, not zero days")
    }

    func testSkipsMedicineWithNoUsableName() {
        XCTAssertNil(FirestoreSchema.medicine(from: [:], remoteID: "a"))
        XCTAssertNil(FirestoreSchema.medicine(from: ["name": "   "], remoteID: "b"))
        // Android's own placeholder for a row it could not read.
        XCTAssertNil(FirestoreSchema.medicine(from: ["name": "Unknown Medicine"], remoteID: "c"))
    }

    func testReadsWholeScheduleDocument() {
        let document: [String: Any] = [
            "updatedAt": "2026-10-06T08:00:00.000",
            "medicines": [
                "idA": ["name": "Metformin"],
                "idB": androidMedicine,
                "idC": ["name": ""],          // unreadable, must be skipped
            ],
        ]
        let medicines = FirestoreSchema.medicines(from: document)
        XCTAssertEqual(medicines.map(\.name), ["Amoxicillin", "Metformin"], "sorted by name, blank dropped")
    }

    func testEmptyScheduleDocumentIsNotAnError() {
        XCTAssertTrue(FirestoreSchema.medicines(from: [:]).isEmpty)
        XCTAssertTrue(FirestoreSchema.medicines(from: ["medicines": [:]]).isEmpty)
    }

    // MARK: - Dates on the wire

    /// `DateTime.now().toIso8601String()` in Dart emits no zone suffix, which
    /// every ISO8601DateFormatter configuration rejects. Android writes
    /// `createdAt` this way, so this is the common case.
    func testParsesFlutterLocalTimestamp() {
        XCTAssertNotNil(FirestoreSchema.date(from: "2026-10-06T08:00:00.000"))
    }

    func testParsesTheOtherTimestampShapesOnTheWire() {
        XCTAssertNotNil(FirestoreSchema.date(from: "2026-10-06T08:00:00.000Z"), "UTC with fractional seconds")
        XCTAssertNotNil(FirestoreSchema.date(from: "2026-10-06T08:00:00Z"), "serverTimestamp round-trip")
        XCTAssertNotNil(FirestoreSchema.date(from: "2026-10-06"), "plain scheduleDate")
        XCTAssertNotNil(FirestoreSchema.date(from: Date()), "Timestamp already converted by the adapter")
        XCTAssertNil(FirestoreSchema.date(from: nil))
        XCTAssertNil(FirestoreSchema.date(from: "not a date"))
    }

    // MARK: - Writing a medicine Android can read

    func testWritesEveryFieldAndroidReads() {
        var medicine = Medicine(name: "Vitamin D3", dosage: "60,000 IU", slots: [.morning])
        medicine.adoptRemoteID("existingDocKey")
        medicine.foodInstruction = .afterFood
        medicine.durationDays = 5
        medicine.startDate = FirestoreSchema.dayFormatter.date(from: "2026-10-06")!

        let fields = FirestoreSchema.fields(for: medicine, on: medicine.startDate)

        // Android reads each of these with a `?? 'default'`; a missing key is
        // silently replaced with a wrong value rather than failing loudly.
        for key in ["id", "name", "dosage", "type", "frequency", "timing", "time",
                    "instructions", "foodInstructions", "isActive", "scheduleDate", "startDate"] {
            XCTAssertNotNil(fields[key], "Android reads '\(key)' — omitting it silently corrupts the row")
        }

        XCTAssertEqual(fields["id"] as? String, "existingDocKey", "must update in place, not fork a new document")
        XCTAssertEqual(fields["name"] as? String, "Vitamin D3")
        XCTAssertEqual(fields["frequency"] as? String, "Once Daily")
        XCTAssertEqual(fields["timing"] as? String, "Morning")
        XCTAssertEqual(fields["foodInstructions"] as? String, "After food")
        XCTAssertEqual(fields["scheduleDate"] as? String, "2026-10-06")
        XCTAssertEqual(fields["endDate"] as? String, "2026-10-10", "5 days from the 6th ends on the 10th, inclusive")
    }

    func testMultipleSlotsAreWrittenInAndroidsTimingFormat() {
        let medicine = Medicine(name: "Amoxicillin", dosage: "500 mg", slots: [.night, .morning])
        let fields = FirestoreSchema.fields(for: medicine)
        XCTAssertEqual(fields["timing"] as? String, "Morning & Night", "clock order, Android's separator")
        XCTAssertEqual(fields["frequency"] as? String, "Twice Daily")
    }

    /// Writing then reading must land back where it started, or one platform
    /// slowly rewrites the other's data.
    func testMedicineRoundTrips() throws {
        var original = Medicine(name: "Metformin", dosage: "850 mg", slots: [.morning, .afternoon, .night])
        // Adoption, not assignment: binding the key also derives `id` from it,
        // so the medicine survives the round trip with the same identity and
        // its scheduled reminders stay attached.
        original.adoptRemoteID("roundTripKey")
        original.foodInstruction = .withFood
        original.instructions = "With meals"
        original.durationDays = 30

        let fields = FirestoreSchema.fields(for: original, on: original.startDate)
        let restored = try XCTUnwrap(FirestoreSchema.medicine(from: fields, remoteID: "roundTripKey"))

        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.dosage, original.dosage)
        XCTAssertEqual(restored.slots.sorted(), original.slots.sorted())
        XCTAssertEqual(restored.foodInstruction, original.foodInstruction)
        XCTAssertEqual(restored.instructions, original.instructions)
        XCTAssertEqual(restored.durationDays, original.durationDays)
        XCTAssertEqual(restored.id, original.id)
    }

    /// The invariant the round trip depends on: a locally created medicine
    /// keeps one identity once it is bound to a document.
    func testAdoptingARemoteIDDerivesTheMatchingUUID() {
        var medicine = Medicine(name: "Aspirin", dosage: "75 mg", slots: [.morning])
        let before = medicine.id

        medicine.adoptRemoteID("newDocKey")

        XCTAssertEqual(medicine.remoteID, "newDocKey")
        XCTAssertEqual(medicine.id, FirestoreSchema.stableUUID(from: "newDocKey"))
        XCTAssertNotEqual(medicine.id, before, "the pre-adoption UUID was random and is deliberately replaced")
    }

    // MARK: - Adherence

    /// Both platforms must derive the same document id, or one dose gets
    /// counted twice — once per platform.
    func testAdherenceDocumentIDMatchesAndroidsFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 6
        components.hour = 8; components.minute = 0
        let scheduledAt = Calendar.current.date(from: components)!

        XCTAssertEqual(
            FirestoreSchema.adherenceDocumentID(medicineRemoteID: "medKey", scheduledAt: scheduledAt),
            "medKey_2026-10-06_08_00"
        )
    }

    func testActionVocabularyMatchesAndroid() {
        XCTAssertEqual(FirestoreSchema.action(for: .taken), "taken")
        XCTAssertEqual(FirestoreSchema.action(for: .skipped), "skipped")
        XCTAssertEqual(FirestoreSchema.action(for: .missed), "missed")

        XCTAssertEqual(FirestoreSchema.outcome(fromAction: "taken"), .taken)
        XCTAssertEqual(FirestoreSchema.outcome(fromAction: "missed"), .missed)
        XCTAssertEqual(FirestoreSchema.outcome(fromAction: "skipped"), .skipped)
        // This app shows `.skipped` as "Dismissed"; a record written under that
        // label must still read back as skipped rather than vanishing.
        XCTAssertEqual(FirestoreSchema.outcome(fromAction: "Dismissed"), .skipped)
        XCTAssertNil(FirestoreSchema.outcome(fromAction: "snoozed"), "snooze is not an adherence outcome")
    }

    /// Exactly what `adherence_service.dart` writes.
    func testReadsAndroidAdherenceRecord() throws {
        let fields: [String: Any] = [
            "userId": "uid123",
            "medicineId": "7bQv2mK1xLpR9dNfTz3A",
            "medicineName": "Amoxicillin",
            "action": "taken",
            "date": "2026-10-06",
            "time": "08:00",
            "notes": "",
            "createdAt": "2026-10-06T08:02:11.000",
            "updatedAt": "2026-10-06T08:02:11.000",
            "synced": false,
            "uniqueId": "7bQv2mK1xLpR9dNfTz3A_2026-10-06_08_00",
        ]

        let record = try XCTUnwrap(FirestoreSchema.doseRecord(from: fields))
        XCTAssertEqual(record.outcome, .taken)
        XCTAssertEqual(record.medicineName, "Amoxicillin")
        XCTAssertEqual(record.medicineID, FirestoreSchema.stableUUID(from: "7bQv2mK1xLpR9dNfTz3A"))
        XCTAssertEqual(record.slot, .morning, "08:00 is the morning slot's default time")
    }

    func testRejectsAdherenceRecordMissingWhatItNeeds() {
        XCTAssertNil(FirestoreSchema.doseRecord(from: ["action": "taken"]), "no medicine or date")
        XCTAssertNil(FirestoreSchema.doseRecord(from: ["medicineId": "x", "date": "2026-10-06"]), "no action")
        XCTAssertNil(
            FirestoreSchema.doseRecord(from: ["medicineId": "x", "date": "06/10/2026", "action": "taken"]),
            "a date in the wrong format is not silently treated as today"
        )
    }

    func testAdherenceRecordRoundTrips() throws {
        let scheduledAt = Calendar.current.date(
            bySettingHour: 20, minute: 0, second: 0, of: Date()
        )!
        let original = DoseRecord(
            id: "ignored",
            medicineID: FirestoreSchema.stableUUID(from: "medKey"),
            medicineName: "Amoxicillin",
            slot: .night,
            scheduledAt: scheduledAt,
            outcome: .taken
        )

        let document = FirestoreSchema.adherenceDocument(
            for: original, userID: "uid123", medicineRemoteID: "medKey"
        )
        let restored = try XCTUnwrap(FirestoreSchema.doseRecord(from: document))

        XCTAssertEqual(restored.outcome, original.outcome)
        XCTAssertEqual(restored.medicineID, original.medicineID)
        XCTAssertEqual(restored.medicineName, original.medicineName)
        XCTAssertEqual(restored.slot, original.slot)
        XCTAssertEqual(
            restored.scheduledAt.timeIntervalSince1970,
            original.scheduledAt.timeIntervalSince1970,
            accuracy: 60,
            "the wire format carries minutes, so seconds are expected to be lost"
        )
    }

    // MARK: - Caretakers

    func testReadsLinkedPatientsFromCaretakerDocument() {
        let document: [String: Any] = [
            "patients": [
                [
                    "uid": "patient1",
                    "name": "Lakshmi Iyer",
                    "email": "lakshmi@example.com",
                    "medicinesCount": 3,
                    "medicinesTaken": 1,
                ],
                // Android caches a patient before its profile has synced, so
                // the name can genuinely be absent.
                ["uid": "patient2", "email": "anand@example.com"],
                ["name": "no uid, unusable"],
            ],
        ]

        let patients = FirestoreSchema.linkedPatients(from: document)
        XCTAssertEqual(patients.count, 2)
        XCTAssertEqual(patients[0].name, "Lakshmi Iyer")
        XCTAssertEqual(patients[0].adherenceRate, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(patients[0].isFallingBehind)
        XCTAssertEqual(patients[1].name, "anand", "falls back to the email local part, as Android does")
        XCTAssertEqual(patients[1].adherenceRate, 0, "no doses recorded is 0%, not a divide by zero")
    }

    func testEmptyCaretakerDocumentIsNotAnError() {
        XCTAssertTrue(FirestoreSchema.linkedPatients(from: [:]).isEmpty)
        XCTAssertTrue(FirestoreSchema.linkedPatients(from: ["patients": []]).isEmpty)
    }

    // MARK: - User profile

    func testReadsUserProfileAndFallsBackToEmailLocalPart() throws {
        let withName = try XCTUnwrap(
            FirestoreSchema.userProfile(from: ["name": "Sanjay R", "email": "s@example.com"], uid: "uid1")
        )
        XCTAssertEqual(withName.name, "Sanjay R")
        XCTAssertEqual(withName.id, "uid1")

        let withoutName = try XCTUnwrap(
            FirestoreSchema.userProfile(from: ["email": "sanjay@example.com"], uid: "uid2")
        )
        XCTAssertEqual(withoutName.name, "sanjay")
    }
}
