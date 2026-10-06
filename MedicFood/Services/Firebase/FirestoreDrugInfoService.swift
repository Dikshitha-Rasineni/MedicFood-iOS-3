import Foundation
import FirebaseFirestore

/// The drug and food-interaction catalogue, from the top-level `medicines`
/// collection — the same rows the Android app's search screen reads.
///
/// Two things about that collection shape the code here:
///
/// 1. **`"NA"` is the empty value.** Rows carry `description: "NA"`,
///    `foodToAvoid: "NA"` and so on rather than omitting the field. Passed
///    through, the UI renders "Avoid: NA" on a card, so it is treated as absent.
/// 2. **`url` holds a base64-encoded JPEG inline.** Fetching the whole
///    collection therefore drags every embedded image across the network. Every
///    query here is bounded, and nothing reads the collection unfiltered.
@MainActor
final class FirestoreDrugInfoService: DrugInfoServicing {

    /// Enough to fill a screen without pulling the catalogue down.
    private static let resultLimit = 40

    func search(_ query: String) async throws -> [DrugInfo] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return try await browse() }

        let snapshot = try await Self.prefixQuery(on: "drugName", matching: text)
            .limit(to: Self.resultLimit)
            .getDocuments()

        return snapshot.documents.compactMap(Self.drugInfo(from:))
    }

    func details(rxcui: String) async throws -> DrugInfo? {
        // `rxcui` carries the catalogue's document id here — these rows are an
        // imported dataset keyed by row number, not by RxNorm concept id.
        let snapshot = try await FirestoreClient.drugCatalogue.document(rxcui).getDocument()
        guard snapshot.exists else { return nil }
        return Self.drugInfo(from: snapshot)
    }

    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] {
        let text = drugName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let snapshot = try await Self.prefixQuery(on: "drugName", matching: text)
            .limit(to: 5)
            .getDocuments()

        return snapshot.documents
            .flatMap { Self.interactions(from: FirestoreClient.normalised($0.data())) }
            .sorted { $0.severity.order < $1.severity.order }
    }

    /// The first screenful, for an empty search box. Ordered by name so it is
    /// stable rather than arbitrary.
    private func browse() async throws -> [DrugInfo] {
        let snapshot = try await FirestoreClient.drugCatalogue
            .order(by: "drugName")
            .limit(to: Self.resultLimit)
            .getDocuments()
        return snapshot.documents.compactMap(Self.drugInfo(from:))
    }

    // MARK: - Queries

    /// Firestore has no "contains", so a prefix range is the closest thing:
    /// everything from the query up to the query plus the highest code point.
    /// Case matters, so the query is capitalised the way the data is.
    private static func prefixQuery(on field: String, matching text: String) -> Query {
        let prefix = text.prefix(1).uppercased() + text.dropFirst().lowercased()
        return FirestoreClient.drugCatalogue
            .whereField(field, isGreaterThanOrEqualTo: prefix)
            .whereField(field, isLessThan: prefix + "\u{f8ff}")
    }

    // MARK: - Mapping

    private static func drugInfo(from document: DocumentSnapshot) -> DrugInfo? {
        let fields = FirestoreClient.normalised(document.data())
        guard let name = value(fields["drugName"]) else { return nil }

        return DrugInfo(
            rxcui: document.documentID,
            name: name,
            synonym: value(fields["searchKey"]),
            form: nil,
            purpose: value(fields["description"]),
            warnings: value(fields["interactingWith"]),
            dosageGuidance: value(fields["timeToTake"])
        )
    }

    private static func interactions(from fields: [String: Any]) -> [FoodInteraction] {
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

    /// The catalogue's placeholders for "no data". Returning them would put
    /// "NA" on screen as though it were a food.
    private static func value(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }

        let placeholders: Set<String> = ["na", "n/a", "nil", "none", "-", "null"]
        return placeholders.contains(text.lowercased()) ? nil : text
    }
}
