import Foundation

/// Turns the shorthand a doctor writes on a prescription into dose slots.
///
/// This is the most domain-specific code in the app and the piece most worth
/// carrying over from the Flutter version verbatim — it encodes real
/// prescribing conventions:
///
/// - **`1-0-1` notation** (morning-afternoon-night), standard across South
///   Asia. `1-0-1` means morning and night, not "one to one".
/// - **Latin abbreviations**: `OD` once daily, `BD`/`BID` twice, `TID`/`TDS`
///   three times, `QID` four times.
/// - Free text: "morning and night", "twice daily".
///
/// Getting this wrong means a patient is reminded at the wrong times, or the
/// wrong number of times a day, so the behaviour is pinned by unit tests in
/// `MedicFoodTests/PrescriptionParserTests.swift`.
enum PrescriptionParser {

    /// Parse a timing string into the slots it means.
    ///
    /// Always returns at least one slot; falls back to `.morning`, matching
    /// the old Dart default.
    static func slots(from timing: String) -> [DoseSlot] {
        let text = timing.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Numeric notation wins, because "1-0-1" is unambiguous where prose
        // is not.
        if let numeric = numericSlots(from: text) {
            return numeric
        }

        var found: [DoseSlot] = []
        if text.contains("early morning") { found.append(.earlyMorning) }
        if text.contains("morning")       { found.append(.morning) }
        if text.contains("afternoon")     { found.append(.afternoon) }
        if text.contains("evening")       { found.append(.evening) }
        if text.contains("night")         { found.append(.night) }
        if text.contains("bed") || text.contains("sleep") { found.append(.beforeSleep) }

        // "early morning" also matches "morning" above; drop the duplicate.
        if found.contains(.earlyMorning) && found.contains(.morning),
           !text.replacingOccurrences(of: "early morning", with: "").contains("morning") {
            found.removeAll { $0 == .morning }
        }

        if found.isEmpty {
            // No slot words at all — fall back to the dose count, so "twice
            // daily" still produces two sensible times.
            if let count = doseCount(from: text) {
                return defaultSlots(forDosesPerDay: count)
            }
            return [.morning]
        }

        return Array(Set(found)).sorted()
    }

    /// Parse `1-0-1` / `1-1-1` / `0-0-1` style notation.
    /// Returns `nil` when the text is not in that form.
    static func numericSlots(from text: String) -> [DoseSlot]? {
        // Three or four hyphen-separated digits.
        guard let range = text.range(
            of: #"\d+-\d+-\d+(-\d+)?"#,
            options: .regularExpression
        ) else { return nil }

        let parts = text[range].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 || parts.count == 4 else { return nil }

        // 3-part is morning-afternoon-night; 4-part adds a bedtime dose.
        let positions: [DoseSlot] = parts.count == 3
            ? [.morning, .afternoon, .night]
            : [.morning, .afternoon, .night, .beforeSleep]

        let slots = zip(parts, positions)
            .filter { $0.0 > 0 }
            .map(\.1)

        return slots.isEmpty ? nil : slots.sorted()
    }

    /// How many doses a day the text asks for, if it says so.
    static func doseCount(from timing: String) -> Int? {
        let text = timing.lowercased()

        if let numeric = numericSlots(from: text) { return numeric.count }

        // Latin abbreviations. Matched on word boundaries — without that,
        // "od" matches inside "food" and every medicine becomes once-daily.
        if matchesWord("qid", in: text) || matchesWord("qds", in: text) { return 4 }
        if matchesWord("tid", in: text) || matchesWord("tds", in: text) { return 3 }
        if matchesWord("bid", in: text) || matchesWord("bd", in: text)  { return 2 }
        if matchesWord("od", in: text)  || matchesWord("qd", in: text)  { return 1 }

        if text.contains("four times")  { return 4 }
        if text.contains("three times") || text.contains("thrice") { return 3 }
        if text.contains("twice") || text.contains("two times") { return 2 }
        if text.contains("once") { return 1 }

        return nil
    }

    /// Sensible slots when all we know is "N times a day".
    static func defaultSlots(forDosesPerDay count: Int) -> [DoseSlot] {
        switch count {
        case ..<1: [.morning]
        case 1:    [.morning]
        case 2:    [.morning, .night]
        case 3:    [.morning, .afternoon, .night]
        case 4:    [.morning, .afternoon, .evening, .night]
        default:   [.earlyMorning, .morning, .afternoon, .evening, .night]
        }
    }

    /// Read the food instruction off free text.
    static func foodInstruction(from text: String) -> FoodInstruction {
        let t = text.lowercased()
        if t.contains("empty stomach") || t.contains("empty") { return .emptyStomach }
        if t.contains("before") { return .beforeFood }
        if t.contains("after")  { return .afterFood }
        if t.contains("with")   { return .withFood }
        return .anyTime
    }

    /// Read the medicine form off free text, including the single-letter
    /// shorthand doctors use (`t` tablet, `c` capsule).
    static func form(from text: String) -> MedicineForm {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        switch t {
        case "t", "tab", "tabs": return .tablet
        case "c", "cap", "caps": return .capsule
        default: break
        }
        if t.contains("tab")   { return .tablet }
        if t.contains("cap")   { return .capsule }
        if t.contains("syr") || t.contains("susp") || t.contains("ml") { return .syrup }
        if t.contains("inj")   { return .injection }
        if t.contains("drop")  { return .drops }
        if t.contains("inhal") || t.contains("puff") { return .inhaler }
        if t.contains("cream") || t.contains("oint") { return .cream }
        return .other
    }

    /// Whole-word match, so `od` does not fire inside `food`.
    private static func matchesWord(_ word: String, in text: String) -> Bool {
        text.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
    }
}
