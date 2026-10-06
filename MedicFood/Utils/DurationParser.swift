import Foundation

/// Turns a prescribed duration ("5 days", "2 weeks", "till finished") into a
/// number of days.
///
/// Ported from the Flutter `DurationHelper`, which was the one piece of that
/// codebase with real unit tests — those tests are carried over too, in
/// `MedicFoodTests/DurationParserTests.swift`, so behaviour is pinned.
///
/// A wrong answer here means a patient gets reminders for the wrong number of
/// days, which is why this is a pure function with no dependencies.
enum DurationParser {

    /// Days per unit. These are the conversions the scheduler assumes —
    /// a month is 30 days, not a calendar month.
    static let unitDays: [String: Int] = [
        "day": 1, "days": 1, "d": 1,
        "week": 7, "weeks": 7, "wk": 7, "wks": 7, "w": 7,
        "month": 30, "months": 30, "mo": 30, "mos": 30, "m": 30,
        "year": 365, "years": 365, "yr": 365, "yrs": 365, "y": 365,
    ]

    /// Phrases that mean "no fixed end date".
    static let indefinitePhrases = [
        "as needed", "as required", "when required", "prn",
        "till finished", "until finished", "till course completes",
        "ongoing", "continuous", "continue", "lifelong", "life long",
        "indefinite", "long term", "long-term", "regular",
    ]

    /// Number of days, or `nil` for an indefinite course.
    ///
    /// `nil` is a meaningful answer, not a failure: it means "keep reminding
    /// until the user stops it".
    static func days(from duration: String) -> Int? {
        let text = normalise(duration)
        guard !text.isEmpty else { return nil }

        if indefinitePhrases.contains(where: { text.contains($0) }) { return nil }

        // Ordered from most specific to least, so "5-7 days" is read as a
        // range before the bare-number rule sees the 5.
        return parseRange(text)
            ?? parseNumberAndUnit(text)
            ?? parseCompact(text)
            ?? parseWordNumber(text)
            ?? parseBareNumber(text)
    }

    /// Lowercase, strip leading verbs and trailing punctuation.
    private static func normalise(_ input: String) -> String {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["for ", "take ", "continue for ", "use for ", "x "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        while let last = text.last, ".,;:".contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// "5-7 days", "2 to 3 weeks" — take the upper bound, so a course is
    /// never cut short.
    private static func parseRange(_ text: String) -> Int? {
        let pattern = #"^(\d+)\s*(?:-|–|to)\s*(\d+)\s*([a-z]+)$"#
        guard let m = firstMatch(pattern, in: text), m.count == 4,
              let upper = Int(m[2]), let per = unitDays[m[3]] else { return nil }
        return upper * per
    }

    /// "5 days", "2 weeks", "1 month".
    private static func parseNumberAndUnit(_ text: String) -> Int? {
        let pattern = #"^(\d+(?:\.\d+)?)\s*([a-z]+)$"#
        guard let m = firstMatch(pattern, in: text), m.count == 3,
              let number = Double(m[1]), let per = unitDays[m[2]] else { return nil }
        return Int((number * Double(per)).rounded())
    }

    /// "5d", "2w", "3m" — no space.
    private static func parseCompact(_ text: String) -> Int? {
        let pattern = #"^(\d+)\s*([dwmy])s?$"#
        guard let m = firstMatch(pattern, in: text), m.count == 3,
              let number = Int(m[1]), let per = unitDays[m[2]] else { return nil }
        return number * per
    }

    private static let wordNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "fourteen": 14, "fifteen": 15, "twenty": 20, "thirty": 30,
    ]

    /// "five days", "two weeks".
    private static func parseWordNumber(_ text: String) -> Int? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let number = wordNumbers[parts[0]],
              let per = unitDays[parts[1]] else { return nil }
        return number * per
    }

    /// A bare number means days.
    private static func parseBareNumber(_ text: String) -> Int? {
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }

    /// Returns the full match plus capture groups, or nil.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
