import Foundation

/// The drug/food catalogue that ships inside the app.
///
/// Reads `drug_food_catalogue.json` from the bundle, so food advice works
/// offline, without signing in, and on any device — none of which is true of
/// the Firestore collection, which sits behind auth rules.
///
/// The JSON uses the same field names as the Firestore `medicines` documents,
/// plus an `aliases` list of brand names ("Dolo" for paracetamol). A real
/// export of that collection can replace the file with no code change.
///
/// **Provenance:** the shipped file was written from general pharmacology
/// knowledge, not exported from a clinical source, and has not been reviewed by
/// a pharmacist. It is for general information, and the screens say so.
@MainActor
final class BundledDrugInfoService: DrugInfoServicing {

    struct Entry: Decodable, Sendable {
        var drugName: String
        var aliases: [String]?
        var description: String?
        var foodToAvoid: String?
        var foodToTake: String?
        var timeToTake: String?
        var interactingWith: String?
        var searchKey: String?

        var fields: [String: Any] {
            [
                "drugName": drugName,
                "description": description ?? "NA",
                "foodToAvoid": foodToAvoid ?? "NA",
                "foodToTake": foodToTake ?? "NA",
                "timeToTake": timeToTake ?? "NA",
                "interactingWith": interactingWith ?? "NA",
                "searchKey": searchKey ?? "NA",
            ]
        }

        /// Every name this drug answers to, folded for comparison.
        var names: [String] {
            ([drugName] + (aliases ?? [])).map(BundledDrugInfoService.fold)
        }
    }

    private(set) var entries: [Entry]

    /// - Parameter entries: injected by tests; `nil` loads the shipped file.
    init(entries: [Entry]? = nil) {
        self.entries = entries ?? Self.loadShipped()
    }

    // MARK: - DrugInfoServicing

    func search(_ query: String) async throws -> [DrugInfo] {
        let text = Self.fold(query)
        guard !text.isEmpty else {
            return entries.sorted { $0.drugName < $1.drugName }.compactMap(info(for:))
        }

        // Names that start with the query come first, then names that merely
        // contain it, so typing "met" puts Metformin above Methotrexate-style
        // mid-word hits.
        let ranked: [(entry: Entry, rank: Int)] = entries.compactMap { entry in
            let names = entry.names
            if names.contains(where: { $0.hasPrefix(text) }) { return (entry, 0) }
            if names.contains(where: { $0.contains(text) }) { return (entry, 1) }
            return nil
        }

        return ranked
            .sorted { ($0.rank, $0.entry.drugName) < ($1.rank, $1.entry.drugName) }
            .compactMap { info(for: $0.entry) }
    }

    func details(rxcui: String) async throws -> DrugInfo? {
        entries.first { Self.id(for: $0) == rxcui }.flatMap(info(for:))
    }

    /// Exact name or brand-name match only.
    ///
    /// Deliberately stricter than `search`. Searching is forgiving because the
    /// user is looking at the results; this lookup is automatic, from a scanned
    /// prescription, and a loose match would attach the wrong drug's advice —
    /// "Vitamin" to "Vitamin D3" — without anyone noticing.
    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] {
        let text = Self.fold(drugName)
        guard !text.isEmpty,
              let entry = entries.first(where: { $0.names.contains(text) })
        else { return [] }

        return DrugCatalogueMapping.interactions(from: entry.fields)
            .sorted { $0.severity.order < $1.severity.order }
    }

    /// Local and instant: autocomplete runs on every pause in typing, so it must
    /// not touch the network — the Firestore search downloads whole documents,
    /// inline images included.
    ///
    /// Each drug contributes at most one line, shown under whichever of its
    /// names matched best: the generic name beats a brand, and a name that
    /// *starts* with the query beats one that merely contains it.
    func suggestions(for query: String, limit: Int) async -> [DrugSuggestion] {
        let text = Self.fold(query)
        guard !text.isEmpty, limit > 0 else { return [] }

        var hits: [(suggestion: DrugSuggestion, rank: Int)] = []

        for entry in entries {
            let names = [entry.drugName] + (entry.aliases ?? [])
            var best: (title: String, rank: Int)?

            for (index, name) in names.enumerated() {
                let folded = Self.fold(name)
                let isGeneric = index == 0
                let rank: Int
                if folded.hasPrefix(text) {
                    rank = isGeneric ? 0 : 1
                } else if folded.contains(text) {
                    rank = isGeneric ? 2 : 3
                } else {
                    continue
                }
                if best == nil || rank < best!.rank { best = (name, rank) }
            }

            guard let best else { continue }
            hits.append((
                DrugSuggestion(
                    title: best.title,
                    subtitle: best.title == entry.drugName ? nil : entry.drugName,
                    completion: entry.drugName
                ),
                best.rank
            ))
        }

        return hits
            .sorted { ($0.rank, $0.suggestion.title.count, $0.suggestion.title)
                    < ($1.rank, $1.suggestion.title.count, $1.suggestion.title) }
            .prefix(limit)
            .map(\.suggestion)
    }

    // MARK: - Helpers

    private func info(for entry: Entry) -> DrugInfo? {
        let brands = (entry.aliases ?? []).prefix(3).joined(separator: ", ")
        return DrugCatalogueMapping.drugInfo(
            id: Self.id(for: entry),
            fields: entry.fields,
            synonym: brands.isEmpty ? nil : brands
        )
    }

    static func id(for entry: Entry) -> String { "bundled-" + fold(entry.drugName) }

    /// Case- and accent-insensitive, so "AMOXICILLIN", "amoxicillin" and
    /// "Amoxicillín" are one drug.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadShipped() -> [Entry] {
        let bundle = Bundle(for: BundledDrugInfoService.self)
        guard let url = bundle.url(forResource: "drug_food_catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            assertionFailure("drug_food_catalogue.json is missing or malformed in the app bundle")
            return []
        }
        return entries
    }
}

/// Tries one catalogue, then another.
///
/// Used on the live backend: Firestore first, because it is the shared source
/// and may be fresher, and the bundled catalogue when Firestore has nothing or
/// cannot be reached — signed out, rules denying the read, no network.
///
/// A failure is still a failure. If the primary throws *and* the fallback has
/// no answer, the error is rethrown rather than turned into an empty result,
/// because "no interactions" and "could not check" are not the same thing and
/// only one of them means a drug has been looked up and found clear.
@MainActor
final class FallbackDrugInfoService: DrugInfoServicing {
    private let primary: DrugInfoServicing
    private let fallback: DrugInfoServicing

    init(primary: DrugInfoServicing, fallback: DrugInfoServicing) {
        self.primary = primary
        self.fallback = fallback
    }

    func search(_ query: String) async throws -> [DrugInfo] {
        try await firstNonEmpty { try await $0.search(query) }
    }

    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] {
        try await firstNonEmpty { try await $0.foodInteractions(for: drugName) }
    }

    /// The one place the order flips: suggestions come from the local
    /// catalogue first. They are asked for on every pause in typing, and the
    /// primary is a network call that can return whole documents.
    func suggestions(for query: String, limit: Int) async -> [DrugSuggestion] {
        let local = await fallback.suggestions(for: query, limit: limit)
        if !local.isEmpty { return local }
        return await primary.suggestions(for: query, limit: limit)
    }

    func details(rxcui: String) async throws -> DrugInfo? {
        if let found = try? await primary.details(rxcui: rxcui) { return found }
        return try await fallback.details(rxcui: rxcui)
    }

    private func firstNonEmpty<T>(
        _ lookup: (DrugInfoServicing) async throws -> [T]
    ) async throws -> [T] {
        var primaryError: Error?
        do {
            let results = try await lookup(primary)
            if !results.isEmpty { return results }
        } catch {
            primaryError = error
        }

        let results = try await lookup(fallback)
        if results.isEmpty, let primaryError { throw primaryError }
        return results
    }
}
