import XCTest
@testable import MedicFood

/// The prescription-shorthand parser had no tests in the Flutter codebase
/// despite being the piece most likely to schedule doses at the wrong times.
final class PrescriptionParserTests: XCTestCase {

    // MARK: - 1-0-1 notation

    func testParsesMorningAndNight() {
        XCTAssertEqual(PrescriptionParser.slots(from: "1-0-1"), [.morning, .night])
    }

    func testParsesAllThree() {
        XCTAssertEqual(
            PrescriptionParser.slots(from: "1-1-1"),
            [.morning, .afternoon, .night]
        )
    }

    func testParsesNightOnly() {
        XCTAssertEqual(PrescriptionParser.slots(from: "0-0-1"), [.night])
    }

    func testParsesMorningOnly() {
        XCTAssertEqual(PrescriptionParser.slots(from: "1-0-0"), [.morning])
    }

    func testFourPartNotationAddsBedtime() {
        XCTAssertEqual(
            PrescriptionParser.slots(from: "1-0-0-1"),
            [.morning, .beforeSleep]
        )
    }

    func testAllZeroesFallsBackRatherThanSchedulingNothing() {
        // A medicine with no doses would never be taken. Falling back to
        // morning is wrong-ish; scheduling nothing is silently broken.
        XCTAssertEqual(PrescriptionParser.slots(from: "0-0-0"), [.morning])
    }

    // MARK: - Latin abbreviations

    func testLatinAbbreviationDoseCounts() {
        XCTAssertEqual(PrescriptionParser.doseCount(from: "OD"), 1)
        XCTAssertEqual(PrescriptionParser.doseCount(from: "BD"), 2)
        XCTAssertEqual(PrescriptionParser.doseCount(from: "BID"), 2)
        XCTAssertEqual(PrescriptionParser.doseCount(from: "TID"), 3)
        XCTAssertEqual(PrescriptionParser.doseCount(from: "TDS"), 3)
        XCTAssertEqual(PrescriptionParser.doseCount(from: "QID"), 4)
    }

    /// Regression guard: a substring match on "od" fires inside "food", which
    /// would turn every "after food" medicine into a once-daily one.
    func testOdDoesNotMatchInsideFood() {
        XCTAssertNil(PrescriptionParser.doseCount(from: "after food"))
    }

    func testAbbreviationsProduceSensibleSlots() {
        XCTAssertEqual(PrescriptionParser.slots(from: "BD"), [.morning, .night])
        XCTAssertEqual(PrescriptionParser.slots(from: "TID"), [.morning, .afternoon, .night])
    }

    // MARK: - Free text

    func testReadsSlotWordsFromText() {
        XCTAssertEqual(PrescriptionParser.slots(from: "morning and night"), [.morning, .night])
        XCTAssertEqual(PrescriptionParser.slots(from: "afternoon"), [.afternoon])
    }

    func testDefaultsToMorningWhenNothingIsRecognised() {
        XCTAssertEqual(PrescriptionParser.slots(from: "whenever"), [.morning])
    }

    func testAlwaysReturnsAtLeastOneSlot() {
        for input in ["", "   ", "???", "0-0-0", "unknown"] {
            XCTAssertFalse(
                PrescriptionParser.slots(from: input).isEmpty,
                "\"\(input)\" produced no slots — that medicine would never be taken"
            )
        }
    }

    // MARK: - Food and form

    func testFoodInstruction() {
        XCTAssertEqual(PrescriptionParser.foodInstruction(from: "before food"), .beforeFood)
        XCTAssertEqual(PrescriptionParser.foodInstruction(from: "after meals"), .afterFood)
        XCTAssertEqual(PrescriptionParser.foodInstruction(from: "with water"), .withFood)
        XCTAssertEqual(PrescriptionParser.foodInstruction(from: "anytime"), .anyTime)
    }

    func testSingleLetterFormShorthand() {
        // Doctors write "t" for tablet and "c" for capsule.
        XCTAssertEqual(PrescriptionParser.form(from: "t"), .tablet)
        XCTAssertEqual(PrescriptionParser.form(from: "c"), .capsule)
        XCTAssertEqual(PrescriptionParser.form(from: "syrup"), .syrup)
        XCTAssertEqual(PrescriptionParser.form(from: "inj"), .injection)
    }
}
