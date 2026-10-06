import XCTest
@testable import MedicFood

/// A model's answer is untrusted input. These pin what the app does with it:
/// accept the shape it asked for, bound everything, and drop what does not fit.
final class AIResponseParserTests: XCTestCase {

    // MARK: - Prescriptions

    private let prescription = """
    {
      "text": "Tab. Amoxicillin 500mg 1-0-1 x 5 days\\nTab. Paracetamol 650mg SOS",
      "medicines": [
        {"name": "Amoxicillin", "dosage": "500 mg", "timing": "1-0-1",
         "form": "tablet", "food": "afterFood", "duration": "5 days"},
        {"name": "Paracetamol", "dosage": "650 mg", "timing": "",
         "form": "tablet", "food": "anyTime", "duration": ""}
      ]
    }
    """

    func testReadsAWellFormedPrescription() throws {
        let reading = try AIResponseParser.prescription(from: prescription)

        XCTAssertEqual(reading.medicines.count, 2)
        XCTAssertEqual(reading.medicines[0].name, "Amoxicillin")
        XCTAssertEqual(reading.medicines[0].dosage, "500 mg")
        XCTAssertEqual(reading.medicines[0].timing, "1-0-1")
        XCTAssertEqual(reading.medicines[0].food, .afterFood)
        XCTAssertEqual(reading.medicines[0].duration, "5 days")
        XCTAssertTrue(reading.text.contains("Amoxicillin 500mg"))
    }

    /// The timing is handed on as written, so the one existing parser decides
    /// the dose slots. Pinned here because a reminder at the wrong time of day
    /// is a medication error.
    func testTimingFlowsThroughTheExistingParser() throws {
        let reading = try AIResponseParser.prescription(from: prescription)
        XCTAssertEqual(PrescriptionParser.slots(from: reading.medicines[0].timing), [.morning, .night])
    }

    func testToleratesACodeFenceAroundTheJSON() throws {
        let fenced = "Here you go:\n```json\n\(prescription)\n```"
        XCTAssertEqual(try AIResponseParser.prescription(from: fenced).medicines.count, 2)
    }

    // MARK: - What gets dropped or bounded

    func testDropsMedicinesWithNoName() throws {
        let json = #"{"text":"","medicines":[{"name":"  "},{"name":""},{"dosage":"5 mg"},{"name":"Aspirin"}]}"#
        let reading = try AIResponseParser.prescription(from: json)
        XCTAssertEqual(reading.medicines.map(\.name), ["Aspirin"])
    }

    func testCapsARunawayList() throws {
        let many = (1...50).map { #"{"name":"Drug\#($0)"}"# }.joined(separator: ",")
        let reading = try AIResponseParser.prescription(from: #"{"medicines":[\#(many)]}"#)
        XCTAssertEqual(reading.medicines.count, AIResponseParser.maxMedicines)
    }

    func testBoundsFieldLengthsAndStripsControlCharacters() throws {
        let long = String(repeating: "x", count: 5000)
        let json = #"{"medicines":[{"name":"Met\u0007formin\u0000","dosage":"\#(long)"}]}"#
        let medicine = try XCTUnwrap(AIResponseParser.prescription(from: json).medicines.first)

        XCTAssertEqual(medicine.name, "Metformin")
        XCTAssertLessThanOrEqual(medicine.dosage.count, 40)
    }

    func testCollapsesWhitespace() throws {
        let json = #"{"medicines":[{"name":"  Vitamin    D3  ","timing":"  morning   and   night "}]}"#
        let medicine = try XCTUnwrap(AIResponseParser.prescription(from: json).medicines.first)
        XCTAssertEqual(medicine.name, "Vitamin D3")
        XCTAssertEqual(medicine.timing, "morning and night")
    }

    /// The model is given a closed vocabulary but is not trusted to use it.
    func testUnknownFormAndFoodFallBackToSafeDefaults() throws {
        let json = #"{"medicines":[{"name":"X","form":"wafer","food":"whenever"}]}"#
        let medicine = try XCTUnwrap(AIResponseParser.prescription(from: json).medicines.first)
        XCTAssertEqual(medicine.form, .tablet)
        XCTAssertEqual(medicine.food, .anyTime)
    }

    func testLooseWordingStillMapsToTheRightForm() throws {
        let json = #"{"medicines":[{"name":"A","form":"Syrup"},{"name":"B","form":"Cap"}]}"#
        let medicines = try AIResponseParser.prescription(from: json).medicines
        XCTAssertEqual(medicines.map(\.form), [.syrup, .capsule])
    }

    // MARK: - Garbage

    func testMalformedResponsesThrowRatherThanReturnNothing() {
        for bad in ["", "not json at all", "{", "}{", #"{"medicines": "oops"}"#, "[1,2,3]"] {
            XCTAssertThrowsError(try AIResponseParser.prescription(from: bad), "\"\(bad)\"") { error in
                XCTAssertEqual(error as? MedicineAIError, .malformedResponse)
            }
        }
    }

    func testAnEmptyAnswerIsNotAnError() throws {
        let reading = try AIResponseParser.prescription(from: #"{"text":"","medicines":[]}"#)
        XCTAssertTrue(reading.medicines.isEmpty)
    }

    // MARK: - Dictation

    func testReadsDictation() throws {
        let json = #"{"medicines":[{"name":"Metformin","dosage":"500 mg","timing":"twice a day","duration":"30 days"}]}"#
        let medicines = try AIResponseParser.dictation(from: json)
        XCTAssertEqual(medicines.first?.timing, "twice a day")
        XCTAssertEqual(PrescriptionParser.slots(from: "twice a day").count, 2)
    }

    // MARK: - Identification

    func testReadsALabel() throws {
        let json = #"""
        {"isMedicine":true,"name":"Dolo 650","genericName":"Paracetamol","strength":"650 mg",
         "form":"tablet","purpose":"Used to relieve pain and reduce fever."}
        """#
        let found = try AIResponseParser.identification(from: json)
        XCTAssertEqual(found.name, "Dolo 650")
        XCTAssertEqual(found.genericName, "Paracetamol")
        XCTAssertEqual(found.strength, "650 mg")
        XCTAssertEqual(found.form, .tablet)
        XCTAssertNotNil(found.purpose)
    }

    func testBlankOptionalFieldsBecomeNil() throws {
        let found = try AIResponseParser.identification(
            from: #"{"isMedicine":true,"name":"Aspirin","genericName":"","strength":" ","purpose":""}"#
        )
        XCTAssertNil(found.genericName)
        XCTAssertNil(found.strength)
        XCTAssertNil(found.purpose)
    }

    /// "Not a medicine" is an answer, and the user is told so in plain words.
    func testReportsAPictureThatIsNotAMedicine() {
        XCTAssertThrowsError(
            try AIResponseParser.identification(from: #"{"isMedicine":false,"name":""}"#)
        ) { error in
            guard case MedicineAIError.nothingFound = error else {
                return XCTFail("expected nothingFound, got \(error)")
            }
        }
    }

    func testReportsALabelWithNoReadableName() {
        XCTAssertThrowsError(
            try AIResponseParser.identification(from: #"{"isMedicine":true,"name":"   "}"#)
        ) { error in
            guard case MedicineAIError.nothingFound = error else {
                return XCTFail("expected nothingFound, got \(error)")
            }
        }
    }

    // MARK: - Mapping the SDK's errors

    private struct Fake: Error { let message: String }

    func testOfflineIsRecognised() {
        XCTAssertEqual(GeminiMedicineAI.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(GeminiMedicineAI.map(URLError(.timedOut)), .offline)
    }

    /// The message the project returns until AI Logic is switched on.
    func testServiceNotEnabledIsRecognised() {
        let error = Fake(message: "Firebase AI Logic API has not been used in project 123 before or it is disabled")
        XCTAssertEqual(GeminiMedicineAI.map(error), .notEnabled)
    }

    func testQuotaIsRecognised() {
        XCTAssertEqual(GeminiMedicineAI.map(Fake(message: "HTTP 429 RESOURCE_EXHAUSTED")), .quotaExceeded)
    }

    func testUnknownErrorsGetAPlainMessageNotTheSDKsOwn() {
        let mapped = GeminiMedicineAI.map(Fake(message: "ProtoBuf decoding failed at byte 41"))
        XCTAssertFalse(mapped.localizedDescription.contains("ProtoBuf"))
    }

    // MARK: - Image preparation

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testLargePhotosAreShrunk() throws {
        let prepared = try AIImagePreparer.prepare(image(width: 4000, height: 3000))
        XCTAssertEqual(max(prepared.size.width, prepared.size.height), AIImagePreparer.maxDimension)
        XCTAssertEqual(prepared.size.width / prepared.size.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testSmallPhotosAreNotEnlarged() throws {
        let prepared = try AIImagePreparer.prepare(image(width: 800, height: 600))
        XCTAssertEqual(prepared.size, CGSize(width: 800, height: 600))
    }

    func testAnEmptyImageIsRejected() {
        XCTAssertThrowsError(try AIImagePreparer.prepare(UIImage()))
    }
}
