import Foundation

/// A drug as returned by a public medicines database.
///
/// Distinct from `Medicine` on purpose: a `Medicine` is something *this user
/// has been prescribed*, with a schedule and a course. A `DrugInfo` is
/// reference data about a substance. The Flutter code blurred the two and had
/// a `Medicine` class buried in the API client that meant this, while
/// prescribed medicines travelled as untyped dictionaries.
struct DrugInfo: Identifiable, Codable, Hashable, Sendable {
    /// RxNorm concept unique identifier.
    var rxcui: String
    var name: String
    var synonym: String?
    var form: String?

    var id: String { rxcui }

    /// What the label says it treats.
    var purpose: String?
    var warnings: String?
    var dosageGuidance: String?
}

/// A food that interacts with a drug.
struct FoodInteraction: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var food: String
    var effect: String
    var severity: Severity

    enum Severity: String, Codable, CaseIterable, Sendable {
        case avoid, caution, minor

        var displayName: String {
            switch self {
            case .avoid:   "Avoid"
            case .caution: "Take care"
            case .minor:   "Minor"
            }
        }

        var order: Int {
            switch self {
            case .avoid: 0
            case .caution: 1
            case .minor: 2
            }
        }
    }
}
