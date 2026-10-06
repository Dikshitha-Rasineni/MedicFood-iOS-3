import Foundation

/// One scheduled dose: a medicine, on a day, in a slot.
///
/// Doses are *derived*, not stored. A 30-day course taken twice daily is one
/// `Medicine` plus a rule, not 60 rows — which is what kept the old Firestore
/// document count low, and is worth preserving.
struct Dose: Identifiable, Hashable, Sendable {
    let medicine: Medicine
    let slot: DoseSlot
    let day: Date

    /// Stable across launches: same medicine + same day + same slot always
    /// gives the same id. Notification identifiers are derived from this, so
    /// changing how it is built orphans every reminder already scheduled on
    /// every installed device.
    var id: String {
        "\(medicine.id.uuidString)-\(Self.dayFormatter.string(from: day))-\(slot.rawValue)"
    }

    /// The exact moment this dose is due.
    var scheduledAt: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let time = medicine.timeComponents(for: slot)
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components) ?? day
    }

    var isOverdue: Bool { scheduledAt < .now }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
}

/// What actually happened to a dose.
///
/// **Snooze is deliberately not a case here.** In the Flutter app snooze and
/// adherence flowed through the same channel, and a snooze being recorded as
/// an adherence event was a real, repeatedly-patched bug — the old code had
/// three separate guard comments warning about it.
///
/// Making the type unable to express it removes the bug class entirely: there
/// is no `.snoozed` to accidentally pass to `AdherenceService`. Snoozing is a
/// *scheduling* action and lives on `NotificationService`, not here.
enum DoseOutcome: String, Codable, CaseIterable, Sendable {
    case taken
    case skipped
    case missed   // never actioned, and the day has passed

    var displayName: String { self == .skipped ? "Dismissed" : rawValue.capitalized }

    /// Only `taken` counts toward the adherence percentage.
    var countsAsAdherent: Bool { self == .taken }
}

/// A recorded outcome for one dose. This is the adherence log.
struct DoseRecord: Identifiable, Codable, Hashable, Sendable {
    var id: String          // matches `Dose.id`
    var medicineID: UUID
    var medicineName: String
    var slot: DoseSlot
    var scheduledAt: Date
    var outcome: DoseOutcome
    var recordedAt: Date = .now
}

/// Adherence figures for a period, computed from `DoseRecord`s.
struct AdherenceStats: Hashable, Sendable {
    var taken: Int = 0
    var skipped: Int = 0
    var missed: Int = 0

    var total: Int { taken + skipped + missed }

    /// 0.0 – 1.0. Returns 1.0 for an empty period rather than 0.0, so a new
    /// user is not greeted with "0% adherence" before taking anything.
    var rate: Double {
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }

    var percentage: Int { Int((rate * 100).rounded()) }
}
