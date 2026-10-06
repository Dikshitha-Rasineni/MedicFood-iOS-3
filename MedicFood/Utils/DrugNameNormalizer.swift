import Foundation

/// Turns the name on a prescription into something the drug catalogue can be
/// searched with.
///
/// This exists because the two ends do not speak the same language. OCR gives
/// back what is printed — `"Tab. AMOXICILLIN 500MG"`, `"Metformin HCl 850 mg"`,
/// `"Vitamin D3 60,000 IU"` — while the catalogue stores a bare, capitalised
/// name: `"Amoxicillin"`. The Firestore lookup is a **case-sensitive prefix
/// query**, so without this almost every real scan misses.
///
/// It deliberately returns *several* candidates rather than one answer. Salt
/// and brand suffixes are where a single guess goes wrong: trimming too little
/// misses `"Metformin"`, trimming too much turns `"Vitamin D3"` into
/// `"Vitamin"`. The caller tries them in order and takes the first that hits.
enum DrugNameNormalizer {

    /// Dose forms doctors prefix, with and without the full stop.
    private static let formPrefixes: Set<String> = [
        "tab", "tabs", "tablet", "tablets",
        "cap", "caps", "capsule", "capsules",
        "syp", "syr", "syrup", "susp", "suspension",
        "inj", "injection", "amp", "ampoule", "vial",
        "oint", "ointment", "cr", "cream", "gel",
        "drop", "drops", "soln", "solution",
        "inh", "inhaler", "puff", "sachet", "powder",
    ]

    /// Units that mark the start of a dose rather than part of a name.
    private static let doseUnits: Set<String> = [
        "mg", "mcg", "µg", "ug", "g", "gm", "kg",
        "ml", "l", "cc", "iu", "iu.", "unit", "units", "u",
        "%", "mg/ml", "mg/5ml",
    ]

    /// Words that are modifiers, not the drug.
    private static let noiseWords: Set<String> = [
        "hcl", "hydrochloride", "sodium", "potassium", "calcium", "sulphate",
        "sulfate", "maleate", "tartrate", "citrate", "succinate", "besylate",
        "sr", "xr", "er", "cr", "la", "md", "dt", "ds", "forte", "plus",
        "oral", "topical", "once", "daily", "bd", "od", "tds", "qid", "hs", "stat",
    ]

    /// Search terms to try, best first.
    ///
    /// Always non-empty for non-empty input: the raw trimmed text is the last
    /// resort, so a name this does not understand is still looked up rather
    /// than silently dropped.
    static func candidates(from raw: String) -> [String] {
        let cleaned = clean(raw)
        var results: [String] = []

        func add(_ value: String) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count >= 3 else { return }
            let cased = capitalised(text)
            if !results.contains(cased) { results.append(cased) }
        }

        add(cleaned)

        // A two-word name like "Vitamin D3" must survive, so the first *two*
        // tokens are tried before falling back to one.
        let tokens = cleaned.split(separator: " ").map(String.init)
        if tokens.count > 2 { add(tokens.prefix(2).joined(separator: " ")) }
        if tokens.count > 1 { add(tokens[0]) }

        add(raw)
        return results
    }

    /// The single best guess — for display, not for searching.
    static func primary(from raw: String) -> String {
        candidates(from: raw).first ?? raw
    }

    // MARK: - Cleaning

    private static func clean(_ raw: String) -> String {
        var text = raw.lowercased()

        // Strip anything parenthesised: "(generic)", "(500mg)".
        text = text.replacingOccurrences(
            of: "\\([^)]*\\)", with: " ", options: .regularExpression
        )

        // Anything after a separator is almost always dosing, not the name.
        for separator in ["-", "—", ":", ",", "/"] {
            if let index = text.firstIndex(of: Character(separator)) {
                // Keep it when the separator is inside a word, as in "co-amoxiclav".
                let before = text[..<index].trimmingCharacters(in: .whitespaces)
                if before.count >= 4 { text = String(text[..<index]) }
            }
        }

        let tokens = text
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)

        var kept: [String] = []
        for token in tokens {
            let word = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "+")))
            if word.isEmpty { continue }

            // A dose form only counts as noise at the front — "Drops" can be
            // part of a name later on.
            if kept.isEmpty && formPrefixes.contains(word) { continue }
            if noiseWords.contains(word) { continue }
            if doseUnits.contains(word) { break }

            // "500mg", "60,000iu", "5ml" — a number glued to a unit ends the name.
            if startsWithDigit(word) { break }

            kept.append(word)
        }

        return kept.joined(separator: " ")
    }

    private static func startsWithDigit(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return first.isNumber
    }

    /// The catalogue stores `"Amoxicillin"`, and the query is case-sensitive,
    /// so the first letter of each word is raised and the rest lowered — except
    /// trailing figures like the `D3` in `"Vitamin D3"`.
    private static func capitalised(_ text: String) -> String {
        text.split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return "" }
                let rest = word.dropFirst()
                // Short alphanumeric tails ("d3", "b12") are upper-cased whole.
                if word.count <= 3 && word.contains(where: \.isNumber) {
                    return word.uppercased()
                }
                return String(first).uppercased() + rest.lowercased()
            }
            .joined(separator: " ")
    }
}
