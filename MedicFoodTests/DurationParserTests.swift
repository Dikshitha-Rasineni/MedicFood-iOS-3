import XCTest
@testable import MedicFood

/// Ported from the Flutter `duration_helper_test.dart` — the one piece of the
/// old codebase that had real tests. Every case there is kept, so a behaviour
/// change shows up as a failure rather than as a patient being reminded for
/// the wrong number of days.
final class DurationParserTests: XCTestCase {

    func testEmptyStringIsIndefinite() {
        XCTAssertNil(DurationParser.days(from: ""))
    }

    func testParsesCalendarPickerFormat() {
        XCTAssertEqual(DurationParser.days(from: "7 days"), 7)
        XCTAssertEqual(DurationParser.days(from: "1 day"), 1)
        XCTAssertEqual(DurationParser.days(from: "30 days"), 30)
    }

    func testIsCaseInsensitiveAndTrimsWhitespace() {
        XCTAssertEqual(DurationParser.days(from: "  7 DAYS  "), 7)
    }

    func testStripsLeadingVerbAndTrailingPunctuation() {
        XCTAssertEqual(DurationParser.days(from: "for 7 days"), 7)
        XCTAssertEqual(DurationParser.days(from: "take 7 days."), 7)
    }

    func testIndefinitePhrasesReturnNil() {
        for phrase in ["as needed", "till finished", "ongoing", "lifelong"] {
            XCTAssertNil(
                DurationParser.days(from: phrase),
                "\"\(phrase)\" should parse as indefinite"
            )
        }
    }

    func testConvertsWeeksAndMonthsToDays() {
        XCTAssertEqual(DurationParser.days(from: "2 weeks"), 14)
        XCTAssertEqual(DurationParser.days(from: "1 month"), 30)
    }

    func testUsesTheCalendarConversionsTheSchedulerAssumes() {
        XCTAssertEqual(DurationParser.unitDays["week"], 7)
        XCTAssertEqual(DurationParser.unitDays["month"], 30)
        XCTAssertEqual(DurationParser.unitDays["year"], 365)
    }

    // MARK: - Cases the Dart parser handled but never tested

    func testParsesRangesByTakingTheUpperBound() {
        // "5-7 days" must not be cut short at 5 — a course ending early is
        // worse than one ending late.
        XCTAssertEqual(DurationParser.days(from: "5-7 days"), 7)
        XCTAssertEqual(DurationParser.days(from: "2 to 3 weeks"), 21)
    }

    func testParsesCompactFormat() {
        XCTAssertEqual(DurationParser.days(from: "5d"), 5)
        XCTAssertEqual(DurationParser.days(from: "2w"), 14)
    }

    func testParsesWordNumbers() {
        XCTAssertEqual(DurationParser.days(from: "five days"), 5)
        XCTAssertEqual(DurationParser.days(from: "two weeks"), 14)
    }

    func testBareNumberMeansDays() {
        XCTAssertEqual(DurationParser.days(from: "10"), 10)
    }
}
