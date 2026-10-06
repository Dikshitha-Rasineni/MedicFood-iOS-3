import XCTest
import UIKit
@testable import MedicFood

// MARK: - Doubles

@MainActor
private final class FakeAI: MedicineAIServicing {
    var isAvailable = true
    var prescription: Result<PrescriptionReading, Error> = .success(PrescriptionReading(text: "", medicines: []))
    var dictation: Result<[AIMedicine], Error> = .success([])
    var identification: Result<MedicineIdentification, Error> = .failure(MedicineAIError.unavailable)

    private(set) var prescriptionCalls = 0
    private(set) var dictationCalls = 0
    private(set) var identifyCalls = 0

    func readPrescription(image: UIImage) async throws -> PrescriptionReading {
        prescriptionCalls += 1; return try prescription.get()
    }
    func readDictation(_ transcript: String) async throws -> [AIMedicine] {
        dictationCalls += 1; return try dictation.get()
    }
    func identifyMedicine(image: UIImage) async throws -> MedicineIdentification {
        identifyCalls += 1; return try identification.get()
    }
}

private final class FakeOCR: PrescriptionOCRServicing, @unchecked Sendable {
    var text: String
    private(set) var calls = 0
    init(text: String) { self.text = text }
    func recognizeText(in image: UIImage) async throws -> String { calls += 1; return text }
}

@MainActor
private final class FailingDrugInfo: DrugInfoServicing {
    struct Offline: LocalizedError { var errorDescription: String? { "Could not reach the server." } }
    func search(_ query: String) async throws -> [DrugInfo] { throw Offline() }
    func details(rxcui: String) async throws -> DrugInfo? { throw Offline() }
    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] { throw Offline() }
}

// MARK: - Helpers

@MainActor
private func prompt(_ decision: AIConsentStore.Decision) -> AIConsentPrompt {
    let store = AIConsentStore(defaults: UserDefaults(suiteName: "ai-test-\(UUID().uuidString)")!)
    store.decision = decision
    return AIConsentPrompt(store: store)
}

private func picture() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    }
}

/// `allow()` and `decline()` resume the held request in a task of their own.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(2)) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

private let amoxicillin = AIMedicine(
    name: "Amoxicillin", dosage: "500 mg", timing: "1-0-1", form: .capsule, food: .afterFood, duration: "5 days"
)

// MARK: - Consent

@MainActor
final class AIConsentTests: XCTestCase {

    func testUndecidedAsksAndDoesNotRunAnything() async {
        let prompt = prompt(.undecided)
        var ranAI = false, ranDevice = false

        await prompt.gate(ai: FakeAI(), withAI: { ranAI = true }, onDevice: { ranDevice = true })

        XCTAssertTrue(prompt.isPresented)
        XCTAssertFalse(ranAI, "nothing may be sent before the user has said yes")
        XCTAssertFalse(ranDevice)
    }

    func testAllowRunsTheHeldRequestWithAIAndIsRemembered() async {
        let prompt = prompt(.undecided)
        var ranAI = false
        await prompt.gate(ai: FakeAI(), withAI: { ranAI = true }, onDevice: {})

        prompt.allow()

        let ran = await eventually { ranAI }
        XCTAssertTrue(ran)
        XCTAssertFalse(prompt.isPresented)

        // Asked once: the next request goes straight through.
        var again = false
        await prompt.gate(ai: FakeAI(), withAI: { again = true }, onDevice: {})
        XCTAssertTrue(again)
        XCTAssertFalse(prompt.isPresented)
    }

    func testDeclineRunsOnDeviceAndIsRemembered() async {
        let prompt = prompt(.undecided)
        var ranDevice = false
        await prompt.gate(ai: FakeAI(), withAI: { XCTFail("must not use AI after a no") }, onDevice: { ranDevice = true })

        prompt.decline()

        let ran = await eventually { ranDevice }
        XCTAssertTrue(ran)

        var again = false
        await prompt.gate(ai: FakeAI(), withAI: { XCTFail("must not use AI after a no") }, onDevice: { again = true })
        XCTAssertTrue(again, "a remembered no must not be asked again")
        XCTAssertFalse(prompt.isPresented)
    }

    /// There is nothing to consent to when no model is wired up.
    func testNoModelMeansNoQuestion() async {
        let ai = FakeAI(); ai.isAvailable = false
        let prompt = prompt(.undecided)
        var ranDevice = false

        await prompt.gate(ai: ai, withAI: { XCTFail("no model") }, onDevice: { ranDevice = true })

        XCTAssertTrue(ranDevice)
        XCTAssertFalse(prompt.isPresented)
    }
}

// MARK: - Scanner

@MainActor
final class ScannerAITests: XCTestCase {

    private func model(ai: FakeAI, ocr: FakeOCR, decision: AIConsentStore.Decision = .allowed) -> PrescriptionScannerViewModel {
        let model = PrescriptionScannerViewModel(ocr: ocr, ai: ai, consent: prompt(decision))
        model.image = picture()
        return model
    }

    func testReadsAPhotoWithAIAndSkipsTheOnDeviceReader() async {
        let ai = FakeAI()
        ai.prescription = .success(PrescriptionReading(text: "Cap Amoxicillin 500mg 1-0-1 x5d", medicines: [amoxicillin]))
        let ocr = FakeOCR(text: "should not be used")
        let model = model(ai: ai, ocr: ocr)

        await model.readPrescription()

        XCTAssertEqual(model.readSource, .gemini)
        XCTAssertEqual(model.drafts.map(\.name), ["Amoxicillin"])
        XCTAssertEqual(model.drafts.first?.dosage, "500 mg")
        XCTAssertEqual(model.drafts.first?.food, .afterFood)
        XCTAssertEqual(model.drafts.first?.durationText, "5 days")
        XCTAssertEqual(model.drafts.first?.slots, [.morning, .night], "timing must reach the dose slots intact")
        XCTAssertEqual(model.extractedText, "Cap Amoxicillin 500mg 1-0-1 x5d")
        XCTAssertEqual(ocr.calls, 0)
        XCTAssertNil(model.aiNotice)
    }

    /// The whole point of keeping the on-device reader: the AI failing must not
    /// leave the person with nothing.
    func testFallsBackToTheOnDeviceReaderWhenTheAIFails() async {
        let ai = FakeAI()
        ai.prescription = .failure(MedicineAIError.offline)
        let ocr = FakeOCR(text: "Tab. Metformin 500mg BD")
        let model = model(ai: ai, ocr: ocr)

        await model.readPrescription()

        XCTAssertEqual(model.readSource, .onDevice)
        XCTAssertEqual(ocr.calls, 1)
        XCTAssertTrue(model.drafts.contains { $0.name.lowercased().contains("metformin") })
        XCTAssertTrue(model.aiNotice?.contains("No internet") ?? false, "the person should be told why: \(String(describing: model.aiNotice))")
    }

    func testAServiceNotSwitchedOnIsExplainedNotHidden() async {
        let ai = FakeAI()
        ai.prescription = .failure(MedicineAIError.notEnabled)
        let model = model(ai: ai, ocr: FakeOCR(text: "Tab. Aspirin 75mg OD"))

        await model.readPrescription()

        XCTAssertEqual(model.readSource, .onDevice)
        XCTAssertNotNil(model.aiNotice)
    }

    func testNoModelMeansOnDeviceAndNoNotice() async {
        let ai = FakeAI(); ai.isAvailable = false
        let model = model(ai: ai, ocr: FakeOCR(text: "Tab. Aspirin 75mg OD"))

        await model.readPrescription()

        XCTAssertEqual(ai.prescriptionCalls, 0)
        XCTAssertEqual(model.readSource, .onDevice)
        XCTAssertNil(model.aiNotice, "AI that was never there needs no explaining")
    }

    func testADeclinedConsentNeverCallsTheAI() async {
        let ai = FakeAI()
        let model = model(ai: ai, ocr: FakeOCR(text: "Tab. Aspirin 75mg OD"), decision: .declined)

        await model.readPrescription()

        XCTAssertEqual(ai.prescriptionCalls, 0)
        XCTAssertEqual(model.readSource, .onDevice)
    }

    func testUndecidedHoldsTheReadUntilTheUserAnswers() async {
        let ai = FakeAI()
        ai.prescription = .success(PrescriptionReading(text: "x", medicines: [amoxicillin]))
        let model = model(ai: ai, ocr: FakeOCR(text: ""), decision: .undecided)

        await model.readPrescription()

        XCTAssertTrue(model.consent.isPresented)
        XCTAssertEqual(ai.prescriptionCalls, 0, "the photo must not leave the phone before consent")

        model.consent.allow()
        let done = await eventually { !model.drafts.isEmpty }
        XCTAssertTrue(done)
        XCTAssertEqual(ai.prescriptionCalls, 1)
    }

    // MARK: Speech and typed text

    /// Speech → words → medicines: what was said lands in the editable box
    /// first, then becomes drafts.
    func testWhatIsSaidBecomesMedicines() async {
        let ai = FakeAI()
        ai.dictation = .success([AIMedicine(name: "Metformin", dosage: "500 mg", timing: "twice a day", duration: "30 days")])
        let model = model(ai: ai, ocr: FakeOCR(text: ""))

        model.dictation.onFinished?("Metformin 500 mg twice a day for 30 days")

        let done = await eventually { !model.drafts.isEmpty }
        XCTAssertTrue(done)
        XCTAssertEqual(model.extractedText, "Metformin 500 mg twice a day for 30 days", "the words must be there to correct")
        XCTAssertEqual(model.drafts.first?.name, "Metformin")
        XCTAssertEqual(model.drafts.first?.slots.count, 2)
        XCTAssertEqual(model.readSource, .gemini)
    }

    func testSpeechFallsBackToTheLocalParserWhenTheAIFails() async {
        let ai = FakeAI()
        ai.dictation = .failure(MedicineAIError.quotaExceeded)
        let model = model(ai: ai, ocr: FakeOCR(text: ""))
        model.extractedText = "Paracetamol 500mg BD"

        await model.extractFromText()

        XCTAssertEqual(model.readSource, .onDevice)
        XCTAssertFalse(model.drafts.isEmpty, "the person must still get something to review")
    }

    func testSilenceDoesNothing() async {
        let ai = FakeAI()
        let model = model(ai: ai, ocr: FakeOCR(text: ""))

        model.dictation.onFinished?("   ")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(ai.dictationCalls, 0)
        XCTAssertTrue(model.drafts.isEmpty)
    }
}

// MARK: - Identify

@MainActor
final class IdentifyMedicineTests: XCTestCase {

    private func model(
        ai: FakeAI,
        ocr: FakeOCR = FakeOCR(text: ""),
        drugInfo: DrugInfoServicing? = nil,
        decision: AIConsentStore.Decision = .allowed
    ) -> IdentifyMedicineViewModel {
        let model = IdentifyMedicineViewModel(
            ai: ai, drugInfo: drugInfo ?? BundledDrugInfoService(), ocr: ocr, consent: prompt(decision)
        )
        model.image = picture()
        return model
    }

    private let dolo = MedicineIdentification(
        name: "Dolo 650", genericName: "Paracetamol", strength: "650 mg", form: .tablet,
        purpose: "Used to relieve pain and reduce fever."
    )

    func testIdentifiesWithAIAndTakesFoodAdviceFromTheCatalogue() async {
        let ai = FakeAI(); ai.identification = .success(dolo)
        let model = model(ai: ai)

        await model.identify()

        guard case .found(let result) = model.phase else { return XCTFail("got \(model.phase)") }
        XCTAssertEqual(result.source, .gemini)
        XCTAssertEqual(result.identification.name, "Dolo 650")

        // The food advice is the catalogue's, found via the generic name.
        guard case .found(let rows, _) = model.food.state else { return XCTFail("got \(model.food.state)") }
        XCTAssertTrue(rows.contains { $0.food.lowercased().contains("alcohol") })
    }

    /// "Not a medicine" is an answer. Falling back to a weaker reader to
    /// re-ask would just produce a worse way of getting the same answer.
    func testNotAMedicineIsReportedWithoutRetryingOnDevice() async {
        let ai = FakeAI(); ai.identification = .failure(MedicineAIError.nothingFound("That does not look like a medicine."))
        let ocr = FakeOCR(text: "Paracetamol")
        let model = model(ai: ai, ocr: ocr)

        await model.identify()

        XCTAssertEqual(model.phase, .failed("That does not look like a medicine."))
        XCTAssertEqual(ocr.calls, 0)
    }

    func testFallsBackToReadingThePackOnDevice() async {
        let ai = FakeAI(); ai.identification = .failure(MedicineAIError.offline)
        let model = model(ai: ai, ocr: FakeOCR(text: "DOLO 650\nParacetamol Tablets IP 650 mg\nMicro Labs"))

        await model.identify()

        guard case .found(let result) = model.phase else { return XCTFail("got \(model.phase)") }
        XCTAssertEqual(result.source, .onDevice)
        XCTAssertEqual(result.identification.name, "Dolo")
        XCTAssertEqual(result.identification.genericName, "Paracetamol")
        XCTAssertEqual(result.identification.strength, "650 mg")
        XCTAssertNotNil(model.aiNotice)
        guard case .found = model.food.state else { return XCTFail("food: \(model.food.state)") }
    }

    func testAPackItCannotMatchSaysSoInsteadOfGuessing() async {
        let ai = FakeAI(); ai.isAvailable = false
        let model = model(ai: ai, ocr: FakeOCR(text: "ZYXOMAB 40\nSome Pharma Ltd"))

        await model.identify()

        guard case .failed = model.phase else { return XCTFail("got \(model.phase)") }
    }

    func testStrengthIsReadOffThePack() {
        XCTAssertEqual(IdentifyMedicineViewModel.strength(in: "Tab 650 mg"), "650 mg")
        XCTAssertEqual(IdentifyMedicineViewModel.strength(in: "Vitamin D3 60,000 IU"), "60,000 IU")
        XCTAssertEqual(IdentifyMedicineViewModel.strength(in: "Syrup 5ml"), "5ml")
        XCTAssertNil(IdentifyMedicineViewModel.strength(in: "No dose here"))
    }

    func testAddingUsesTheGenericNameSoLaterFoodLookupsHit() async {
        let ai = FakeAI(); ai.identification = .success(dolo)
        let model = model(ai: ai)
        await model.identify()

        let prefill = model.prefill()
        XCTAssertEqual(prefill?.name, "Paracetamol")
        XCTAssertEqual(prefill?.dosage, "650 mg")
    }

    /// A failed lookup must not read as "nothing to avoid".
    func testAFailedFoodLookupIsNotReportedAsClear() async {
        let ai = FakeAI(); ai.identification = .success(dolo)
        let model = model(ai: ai, drugInfo: FailingDrugInfo())

        await model.identify()

        guard case .failed = model.food.state else { return XCTFail("food: \(model.food.state)") }
    }

    func testNothingIsSentBeforeConsent() async {
        let ai = FakeAI(); ai.identification = .success(dolo)
        let model = model(ai: ai, decision: .undecided)

        await model.identify()

        XCTAssertTrue(model.consent.isPresented)
        XCTAssertEqual(ai.identifyCalls, 0)
    }
}
