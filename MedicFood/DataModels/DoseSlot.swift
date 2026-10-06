import Foundation

/// The times of day a medicine can be scheduled for.
///
/// This is a **closed vocabulary** and deliberately so. The Flutter code kept
/// these as free-form lowercase strings (`"morning & night"`) and switched on
/// them in a dozen places, which meant a typo silently produced a medicine
/// nobody was ever reminded about. As an enum, the compiler catches that.
///
/// Ordering follows the clock, so `sorted()` gives a sensible dose order.
enum DoseSlot: String, Codable, CaseIterable, Comparable, Sendable {
    case earlyMorning
    case morning
    case afternoon
    case evening
    case night
    case beforeSleep
    case midnight

    /// The default clock time for this slot.
    ///
    /// These values match the Flutter `TimingUtils.convertTimingToTime` table
    /// exactly — patients already have habits built around them, so changing a
    /// time here changes when a real person takes a real tablet.
    var defaultTime: DateComponents {
        switch self {
        case .earlyMorning: DateComponents(hour: 6, minute: 0)
        case .morning:      DateComponents(hour: 8, minute: 0)
        case .afternoon:    DateComponents(hour: 14, minute: 0)
        case .evening:      DateComponents(hour: 18, minute: 0)
        case .night:        DateComponents(hour: 20, minute: 0)
        case .beforeSleep:  DateComponents(hour: 22, minute: 0)
        case .midnight:     DateComponents(hour: 0, minute: 0)
        }
    }

    var displayName: String {
        switch self {
        case .earlyMorning: "Early Morning"
        case .morning:      "Morning"
        case .afternoon:    "Afternoon"
        case .evening:      "Evening"
        case .night:        "Night"
        case .beforeSleep:  "Before Sleep"
        case .midnight:     "Midnight"
        }
    }

    var symbolName: String {
        switch self {
        case .earlyMorning: "sunrise"
        case .morning:      "sun.max"
        case .afternoon:    "sun.min"
        case .evening:      "sunset"
        case .night:        "moon"
        case .beforeSleep:  "bed.double"
        case .midnight:     "moon.stars"
        }
    }

    /// Sort by time of day, not by declaration order, so midnight lands last
    /// rather than wherever it happens to sit in the enum.
    private var sortKey: Int {
        let c = defaultTime
        let hour = c.hour ?? 0
        // Midnight (00:00) belongs at the end of the day, not the start.
        return (hour == 0 ? 24 : hour) * 60 + (c.minute ?? 0)
    }

    static func < (lhs: DoseSlot, rhs: DoseSlot) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}
