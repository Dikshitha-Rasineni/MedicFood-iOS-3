import Foundation

/// What form the medicine takes. Used for the icon and for dose wording
/// ("1 tablet" vs "5 ml").
enum MedicineForm: String, Codable, CaseIterable, Sendable {
    case tablet, capsule, syrup, injection, drops, inhaler, cream, ointment, powder, other

    var displayName: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .tablet, .capsule: "pills"
        case .syrup:            "drop.fill"
        case .injection:        "syringe"
        case .drops:            "eyedropper"
        case .inhaler:          "lungs"
        case .cream:            "bandage"
        case .ointment:         "bandage.fill"
        case .powder:           "testtube.2"
        case .other:            "cross.case"
        }
    }
}

/// Whether the medicine must be taken around food.
enum FoodInstruction: String, Codable, CaseIterable, Sendable {
    case beforeFood, afterFood, withFood, emptyStomach, anyTime

    var displayName: String {
        switch self {
        case .beforeFood: "Before food"
        case .afterFood:  "After food"
        case .withFood:   "With food"
        case .emptyStomach: "Empty stomach"
        case .anyTime:    "Any time"
        }
    }
}

/// A prescribed medicine.
///
/// This is the type the Flutter codebase never had. There, a medicine was a
/// `Map<String, dynamic>` passed through 31,000 lines, every field read as a
/// string literal with a `?? 'default'` fallback and no compiler checking.
/// `docs/ARCHITECTURE.md` in the old repo called it "the single biggest source
/// of fragility in the codebase" and recommended exactly this fix.
struct Medicine: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var dosage: String
    var form: MedicineForm = .tablet

    /// Which slots of the day this is taken in. Never empty for a valid
    /// medicine — `PrescriptionParser` falls back to `.morning`.
    var slots: [DoseSlot]

    var foodInstruction: FoodInstruction = .anyTime
    var instructions: String?

    var startDate: Date = Calendar.current.startOfDay(for: .now)

    /// `nil` means indefinite ("ongoing", "as needed", "till finished").
    /// A fixed number means the course ends, and reminders stop.
    var durationDays: Int?

    var isActive: Bool = true
    var isFromPrescription: Bool = false

    /// Exact clock time per slot, when the user has chosen one. A slot with no
    /// entry falls back to `DoseSlot.defaultTime`. Optional so medicines saved
    /// before this existed still decode.
    var customTimes: [DoseTime]?

    /// `nil` is treated as ON, so existing medicines keep their reminders.
    var remindersEnabled: Bool?

    /// File names inside the app's documents folder (not absolute paths, which
    /// change between installs).
    var prescriptionImagePath: String?
    var frontImagePath: String?
    var backImagePath: String?
    var voiceFilePath: String?

    var isReminderOn: Bool { remindersEnabled ?? true }

    func minutesOfDay(for slot: DoseSlot) -> Int {
        let t = timeComponents(for: slot)
        return (t.hour ?? 0) * 60 + (t.minute ?? 0)
    }

    /// "Morning 8:00 AM, Night 8:00 PM" — the exact times, in clock order.
    var exactTimesDescription: String {
        slots
            .sorted { minutesOfDay(for: $0) < minutesOfDay(for: $1) }
            .map { slot in
                let t = timeComponents(for: slot)
                let date = Calendar.current.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: .now) ?? .now
                return "\(slot.displayName) \(date.formatted(date: .omitted, time: .shortened))"
            }
            .joined(separator: ", ")
    }

    /// The next moment a dose is due, or `nil` if the course is over / paused.
    func nextDose(after now: Date = .now) -> Date? {
        let calendar = Calendar.current
        for offset in 0..<90 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  isScheduled(on: day) else { continue }
            let upcoming = slots.compactMap { slot -> Date? in
                let t = timeComponents(for: slot)
                return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day)
            }.filter { $0 > now }
            if let first = upcoming.min() { return first }
        }
        return nil
    }

    /// The clock time a slot is taken at: the user's choice, else the default.
    func timeComponents(for slot: DoseSlot) -> DateComponents {
        if let custom = customTimes?.first(where: { $0.slot == slot }) {
            return DateComponents(hour: custom.hour, minute: custom.minute)
        }
        return slot.defaultTime
    }

    /// Last day of the course, or `nil` when indefinite.
    var endDate: Date? {
        guard let durationDays else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: durationDays - 1,
            to: startDate
        )
    }

    /// Whether this medicine should produce doses on the given day.
    func isScheduled(on date: Date) -> Bool {
        guard isActive else { return false }
        let day = Calendar.current.startOfDay(for: date)
        guard day >= Calendar.current.startOfDay(for: startDate) else { return false }
        guard let endDate else { return true }   // indefinite course
        return day <= Calendar.current.startOfDay(for: endDate)
    }

    /// How many doses per day, i.e. the frequency.
    var dosesPerDay: Int { slots.count }

    var frequencyDescription: String {
        switch slots.count {
        case 1: "Once daily"
        case 2: "Twice daily"
        case 3: "Three times daily"
        case 4: "Four times daily"
        default: "\(slots.count) times daily"
        }
    }

    /// "Morning & Night" — the human-readable timing summary.
    var timingDescription: String {
        slots.sorted().map(\.displayName).joined(separator: " & ")
    }
}

/// An exact time of day for one slot, e.g. Morning at 8:30.
struct DoseTime: Codable, Hashable, Sendable {
    var slot: DoseSlot
    var hour: Int
    var minute: Int
}
