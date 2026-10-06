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


/// One line of autocomplete.
///
/// Typing "dol" should offer "Dolo", and choosing it should search for
/// *Paracetamol* — the brand is what the user knows, the generic is what the
/// catalogue is keyed by. So a suggestion carries what to show and, separately,
/// what to search for.
struct DrugSuggestion: Identifiable, Hashable, Sendable {
    /// What matched, as shown: a drug name or one of its brand names.
    let title: String
    /// The drug a brand name belongs to; `nil` when `title` is the drug itself.
    let subtitle: String?
    /// What choosing this puts in the search box: always the drug's own name.
    let completion: String

    var id: String { title + "\u{1F}" + completion }

    /// Drop suggestions with nothing left to complete.
    ///
    /// Once the box holds exactly "Paracetamol", offering "Paracetamol" again
    /// is noise — and without this, picking a suggestion would immediately
    /// summon the same suggestion back.
    static func pruned(_ suggestions: [DrugSuggestion], query: String) -> [DrugSuggestion] {
        let typed = query.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return suggestions.filter { suggestion in
            let title = suggestion.title
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return !(title == typed && suggestion.subtitle == nil)
        }
    }
}
