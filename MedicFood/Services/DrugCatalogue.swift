import Foundation

/// How a row of the drug/food catalogue becomes what the app shows.
///
/// One mapping, used by both the Firestore service and the bundled catalogue,
/// so the two cannot disagree about what counts as "avoid" or what `"NA"`
/// means. The row shape is the one the Android app already reads from the
/// `medicines` collection: `drugName`, `description`, `foodToAvoid`,
/// `foodToTake`, `timeToTake`, `interactingWith`, `searchKey`.
enum DrugCatalogueMapping {

    /// The catalogue's placeholders for "no data". Returning them would put
    /// "NA" on screen as though it were a food.
    static func value(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }

        let placeholders: Set<String> = ["na", "n/a", "nil", "none", "-", "null"]
        return placeholders.contains(text.lowercased()) ? nil : text
    }

    static func drugInfo(id: String, fields: [String: Any], synonym: String? = nil) -> DrugInfo? {
        guard let name = value(fields["drugName"]) else { return nil }

        return DrugInfo(
            rxcui: id,
            name: name,
            synonym: synonym ?? value(fields["searchKey"]),
            form: nil,
            purpose: value(fields["description"]),
            warnings: value(fields["interactingWith"]),
            dosageGuidance: value(fields["timeToTake"])
        )
    }

    static func interactions(from fields: [String: Any]) -> [FoodInteraction] {
        var results: [FoodInteraction] = []

        if let avoid = value(fields["foodToAvoid"]) {
            results.append(FoodInteraction(
                food: avoid,
                effect: value(fields["interactingWith"]) ?? "Avoid while taking this medicine.",
                severity: .avoid
            ))
        }
        if let take = value(fields["foodToTake"]) {
            results.append(FoodInteraction(
                food: take,
                effect: value(fields["timeToTake"]) ?? "Recommended while taking this medicine.",
                severity: .minor
            ))
        }
        return results
    }
}
