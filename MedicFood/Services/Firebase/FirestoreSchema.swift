import Foundation
import CryptoKit

/// Translation between this app's domain types and the Firestore documents the
/// **Android/Flutter app already writes** in project `medicfood-84cbf`.
///
/// Both apps share one backend, so this file is not a design — it is a
/// transcription. Every key here was read out of the Flutter sources
/// (`lib/services/medicine_service.dart`, `adherence_service.dart`). If a key
/// looks wrong, the fix is to check Android, not to rename it here: a rename
/// silently stops the two apps seeing each other's data.
///
/// Deliberately free of any Firebase import. It maps `[String: Any]` in and
/// out, which is what makes it unit-testable with no network, no SDK and no
/// `GoogleService-Info.plist` — the Firebase adapters are then a thin shell
/// that only fetches dictionaries and hands them here.
enum FirestoreSchema {

    // MARK: - Paths
    //
    // users/{uid}
    //   └── medicine_schedules/current_schedule   ← ALL medicines, one document
    //   └── adherence/{medicineId}_{date}_{time}

    enum Path {
        static let users = "users"
        static let medicineSchedules = "medicine_schedules"
        /// Android keeps every medicine inside this single document, as a map
        /// under `medicines`. See the note on `medicines(from:)`.
        static let currentSchedule = "current_schedule"
        static let adherence = "adherence"
    }

    // MARK: - Dates

    /// `scheduleDate` and the adherence `date` field are plain `yyyy-MM-dd`
    /// strings on Android, not timestamps.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Android writes `HH:mm` for the adherence `time` field, but `hh:mm a`
    /// ("08:00 AM") for a medicine's `time`. Both appear; both are read.
    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let displayClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "hh:mm a"
        return f
    }()

    /// `createdAt` / `updatedAt` are ISO-8601 strings in some writes and
    /// `serverTimestamp()` in others, so a reader must accept both. The
    /// Firebase adapter converts `Timestamp` to `Date` before calling in,
    /// which is why `Date` is handled here without importing the SDK.
    static func date(from value: Any?) -> Date? {
        switch value {
        case let date as Date: return date
        case let string as String:
            return ISO8601DateFormatter.flexible.date(from: string)
                ?? ISO8601DateFormatter.plain.date(from: string)
                ?? localISOFormatter.date(from: string)
                ?? dayFormatter.date(from: string)
        case let seconds as Double: return Date(timeIntervalSince1970: seconds)
        default: return nil
        }
    }

    // MARK: - Identity

    /// Android medicine ids are Firestore's own 20-character ids; this app's
    /// `Medicine.id` is a `UUID`. The two must agree permanently, because
    /// `Dose.id` is built from the UUID and every scheduled notification is
    /// keyed by it — a medicine that changed id on each sync would orphan all
    /// of its reminders.
    ///
    /// So the UUID is *derived* from the Firestore id rather than generated:
    /// the same document always produces the same UUID, on every device and
    /// every launch, with no mapping table to keep.
    static func stableUUID(from remoteID: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data(remoteID.utf8)).prefix(16))
        // Set the RFC 4122 version (5) and variant bits so the result is a
        // well-formed name-based UUID rather than 16 arbitrary bytes.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    // MARK: - Medicines (read)

    /// Pull every medicine out of the `current_schedule` document.
    ///
    /// Android stores them as a **map keyed by medicine id** under `medicines`,
    /// not as a subcollection — so the whole list arrives in one document read.
    /// That is cheap to read and badly behaved to write (see `scheduleDocument`),
    /// but it is the shape on the wire and this app has to match it.
    static func medicines(from document: [String: Any]) -> [Medicine] {
        guard let raw = document["medicines"] as? [String: Any] else { return [] }
        return raw.compactMap { key, value in
            guard let fields = value as? [String: Any] else { return nil }
            return medicine(from: fields, remoteID: key)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One entry of the `medicines` map → a `Medicine`.
    ///
    /// Every field is optional on the wire. The Flutter code reads each one as
    /// `?? 'default'`, so documents genuinely do arrive with fields missing and
    /// a strict decode would drop real medicines on the floor.
    static func medicine(from fields: [String: Any], remoteID: String) -> Medicine? {
        let name = (fields["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A nameless medicine cannot be shown or reminded about; skipping it is
        // better than rendering "Unknown Medicine" rows the user cannot act on.
        guard !name.isEmpty, name != "Unknown Medicine" else { return nil }

        // `timing` is free-form on Android ("Morning", "morning & night"), which
        // is exactly what PrescriptionParser already normalises into slots.
        let timing = fields["timing"] as? String ?? ""
        var slots = PrescriptionParser.slots(from: timing)
        if timing.isEmpty, let frequency = fields["frequency"] as? String,
           let count = PrescriptionParser.doseCount(from: frequency) {
            slots = PrescriptionParser.defaultSlots(forDosesPerDay: count)
        }

        let foodText = fields["foodInstructions"] as? String ?? fields["foodInstruction"] as? String ?? ""
        let formText = fields["type"] as? String ?? fields["form"] as? String ?? ""

        var medicine = Medicine(
            id: stableUUID(from: remoteID),
            name: name,
            dosage: fields["dosage"] as? String ?? "",
            form: formText.isEmpty ? .tablet : PrescriptionParser.form(from: formText),
            slots: slots,
            foodInstruction: foodText.isEmpty ? .anyTime : PrescriptionParser.foodInstruction(from: foodText),
            instructions: (fields["instructions"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            startDate: startDate(from: fields),
            durationDays: durationDays(from: fields),
            isActive: fields["isActive"] as? Bool ?? true,
            isFromPrescription: fields["isFromPrescription"] as? Bool ?? false
        )
        medicine.remoteID = remoteID

        // A per-slot clock time, when Android recorded one.
        if let timeText = fields["time"] as? String, let slot = slots.first,
           let components = timeComponents(from: timeText) {
            medicine.customTimes = [DoseTime(slot: slot, hour: components.hour, minute: components.minute)]
        }
        return medicine
    }

    /// Android writes `duration` as free text ("5 days", "1 week") and also
    /// carries `startDate` / `endDate`. Prefer the explicit dates, because a
    /// course edited on Android updates those and may leave `duration` stale.
    static func durationDays(from fields: [String: Any]) -> Int? {
        if let start = date(from: fields["startDate"]), let end = date(from: fields["endDate"]) {
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day
            // +1: Android's endDate is the last day the medicine is taken,
            // inclusive, so a 5-day course spans start…start+4.
            if let days, days >= 0 { return days + 1 }
        }
        if let text = fields["duration"] as? String { return DurationParser.days(from: text) }
        return nil
    }

    static func startDate(from fields: [String: Any]) -> Date {
        let value = date(from: fields["startDate"])
            ?? date(from: fields["scheduleDate"])
            ?? date(from: fields["createdAt"])
            ?? .now
        return Calendar.current.startOfDay(for: value)
    }

    /// "08:00 AM" or "08:00" → hour/minute.
    static func timeComponents(from text: String) -> (hour: Int, minute: Int)? {
        let parsed = displayClockFormatter.date(from: text) ?? clockFormatter.date(from: text)
        guard let parsed else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        guard let hour = c.hour, let minute = c.minute else { return nil }
        return (hour, minute)
    }

    // MARK: - Medicines (write)

    /// A `Medicine` → one entry of the `medicines` map.
    ///
    /// Written to look exactly like Android's own writes, including the fields
    /// this app does not itself use (`frequency`, `type`, `scheduleDates`), so
    /// an Android client reading a medicine added on iOS sees a complete
    /// document rather than one full of its `?? 'default'` fallbacks.
    static func fields(for medicine: Medicine, on day: Date = .now) -> [String: Any] {
        let scheduleDate = dayFormatter.string(from: day)
        let slot = medicine.slots.sorted().first ?? .morning
        let time = medicine.timeComponents(for: slot)

        var fields: [String: Any] = [
            "id": medicine.remoteID ?? medicine.id.uuidString,
            "name": medicine.name,
            "dosage": medicine.dosage,
            "type": medicine.form.displayName,
            "timing": medicine.slots.sorted().map(\.displayName).joined(separator: " & "),
            "frequency": frequencyText(forDosesPerDay: medicine.slots.count),
            "time": displayClockFormatter.string(
                from: Calendar.current.date(bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: day) ?? day
            ),
            "instructions": medicine.instructions ?? "",
            "foodInstructions": medicine.foodInstruction.displayName,
            "isActive": medicine.isActive,
            "isFromPrescription": medicine.isFromPrescription,
            "scheduleDate": scheduleDate,
            "startDate": dayFormatter.string(from: medicine.startDate),
        ]

        if let durationDays = medicine.durationDays,
           let end = Calendar.current.date(byAdding: .day, value: durationDays - 1, to: medicine.startDate) {
            fields["duration"] = "\(durationDays) days"
            fields["endDate"] = dayFormatter.string(from: end)
        }
        return fields
    }

    /// Android's `frequency` is a display string, not a number.
    static func frequencyText(forDosesPerDay count: Int) -> String {
        switch count {
        case ...1: "Once Daily"
        case 2:    "Twice Daily"
        case 3:    "Three times Daily"
        case 4:    "Four times Daily"
        default:   "\(count) times Daily"
        }
    }

    /// One entry of a medicine's `scheduleData` array — Android materialises a
    /// row per calendar date rather than deriving doses from the slots.
    static func scheduleEntry(date: Date, isCompleted: Bool = false, notes: String = "") -> [String: Any] {
        [
            "date": dayFormatter.string(from: date),
            "isCompleted": isCompleted,
            "completedAt": NSNull(),
            "notes": notes,
        ]
    }

    // MARK: - Adherence

    /// Android's document id. Rebuilt rather than stored, so a record written
    /// on either platform lands on the same document and the two cannot
    /// double-count one dose.
    ///
    /// Shape: `{medicineId}_{yyyy-MM-dd}_{HH_mm}` — note the colon in the time
    /// is replaced with an underscore, because `/` and `:` are awkward in ids.
    static func adherenceDocumentID(medicineRemoteID: String, scheduledAt: Date) -> String {
        let day = dayFormatter.string(from: scheduledAt)
        let time = clockFormatter.string(from: scheduledAt).replacingOccurrences(of: ":", with: "_")
        return "\(medicineRemoteID)_\(day)_\(time)"
    }

    /// `DoseOutcome` ↔ Android's `action`. The three cases match one-for-one,
    /// which is luck rather than design — check this mapping if either side
    /// gains a case.
    static func action(for outcome: DoseOutcome) -> String {
        switch outcome {
        case .taken:   "taken"
        case .skipped: "skipped"
        case .missed:  "missed"
        }
    }

    static func outcome(fromAction action: String) -> DoseOutcome? {
        switch action.lowercased() {
        case "taken":             .taken
        case "skipped", "dismissed": .skipped
        case "missed":            .missed
        default:                  nil
        }
    }

    static func adherenceDocument(for record: DoseRecord, userID: String, medicineRemoteID: String) -> [String: Any] {
        let documentID = adherenceDocumentID(medicineRemoteID: medicineRemoteID, scheduledAt: record.scheduledAt)
        return [
            "userId": userID,
            "medicineId": medicineRemoteID,
            "medicineName": record.medicineName,
            "action": action(for: record.outcome),
            "date": dayFormatter.string(from: record.scheduledAt),
            "time": clockFormatter.string(from: record.scheduledAt),
            "notes": "",
            "createdAt": ISO8601DateFormatter.flexible.string(from: record.recordedAt),
            "updatedAt": ISO8601DateFormatter.flexible.string(from: record.recordedAt),
            // Android sets this false and sweeps later; iOS writes straight to
            // Firestore, so the row is already durable when it lands.
            "synced": true,
            "uniqueId": documentID,
        ]
    }

    static func doseRecord(from fields: [String: Any], medicines: [UUID: Medicine] = [:]) -> DoseRecord? {
        guard let action = fields["action"] as? String,
              let outcome = outcome(fromAction: action),
              let remoteID = fields["medicineId"] as? String,
              let dayText = fields["date"] as? String,
              let day = dayFormatter.date(from: dayText)
        else { return nil }

        let medicineID = stableUUID(from: remoteID)
        let timeText = fields["time"] as? String ?? "08:00"
        let components = timeComponents(from: timeText) ?? (hour: 8, minute: 0)
        let scheduledAt = Calendar.current.date(
            bySettingHour: components.hour, minute: components.minute, second: 0, of: day
        ) ?? day

        // The slot is not stored on Android, so it is recovered from the
        // medicine's own slots by closest scheduled time; failing that, from
        // the clock time alone.
        let slot = medicines[medicineID]?.slots.min(by: { lhs, rhs in
            let minutes = components.hour * 60 + components.minute
            return abs(slotMinutes(lhs) - minutes) < abs(slotMinutes(rhs) - minutes)
        }) ?? nearestSlot(toHour: components.hour, minute: components.minute)

        return DoseRecord(
            id: "\(medicineID.uuidString)-\(dayText)-\(slot.rawValue)",
            medicineID: medicineID,
            medicineName: fields["medicineName"] as? String ?? medicines[medicineID]?.name ?? "",
            slot: slot,
            scheduledAt: scheduledAt,
            outcome: outcome,
            recordedAt: date(from: fields["createdAt"]) ?? scheduledAt
        )
    }

    private static func slotMinutes(_ slot: DoseSlot) -> Int {
        (slot.defaultTime.hour ?? 0) * 60 + (slot.defaultTime.minute ?? 0)
    }

    static func nearestSlot(toHour hour: Int, minute: Int) -> DoseSlot {
        let target = hour * 60 + minute
        return DoseSlot.allCases.min { abs(slotMinutes($0) - target) < abs(slotMinutes($1) - target) } ?? .morning
    }

    // MARK: - User profile

    static func userProfile(from fields: [String: Any], uid: String) -> UserProfile? {
        let email = fields["email"] as? String ?? ""
        let name = fields["name"] as? String ?? email.components(separatedBy: "@").first ?? ""
        return UserProfile(id: uid, name: name, email: email)
    }

    static func userDocument(for profile: UserProfile, shareCode: String?) -> [String: Any] {
        var fields: [String: Any] = [
            "name": profile.name,
            "email": profile.email,
        ]
        if let shareCode { fields["shareCode"] = shareCode }
        return fields
    }

    // MARK: - Caretakers

    /// Android keeps linked patients as an array of maps on the caretaker's own
    /// user document, each a cached copy of the patient's profile plus two
    /// running counters the patient's app updates.
    static func linkedPatients(from document: [String: Any]) -> [LinkedPatient] {
        guard let raw = document["patients"] as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let uid = entry["uid"] as? String else { return nil }
            let total = entry["medicinesCount"] as? Int ?? 0
            let taken = entry["medicinesTaken"] as? Int ?? 0
            return LinkedPatient(
                id: uid,
                name: entry["name"] as? String
                    ?? (entry["email"] as? String)?.components(separatedBy: "@").first
                    ?? "Dependent",
                adherenceRate: total > 0 ? Double(taken) / Double(total) : 0,
                dosesToday: total,
                takenToday: taken,
                lastActive: date(from: entry["lastSync"])
            )
        }
    }
}

extension FirestoreSchema {
    /// `DateTime.now().toIso8601String()` on a *local* Dart DateTime emits no
    /// zone suffix at all ("2026-10-06T08:00:00.000"), which every
    /// `ISO8601DateFormatter` configuration rejects. Android writes
    /// `createdAt` that way, so this is the common case, not an edge case.
    static let localISOFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()
}

extension ISO8601DateFormatter {
    /// Flutter's `toIso8601String()` includes fractional seconds; the default
    /// `ISO8601DateFormatter` rejects them.
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// A UTC timestamp with no fractional part, which `serverTimestamp()`
    /// round-trips produce.
    static let plain = ISO8601DateFormatter()
}
