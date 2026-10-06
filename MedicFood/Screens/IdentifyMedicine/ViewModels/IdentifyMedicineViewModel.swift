import UIKit
import Observation

/// Photograph a medicine pack and find out what it is and what to eat or avoid
/// with it.
///
/// Two readers, in order:
///
/// 1. **Gemini**, when the user has allowed it: reads the label, and writes a
///    one-line description.
/// 2. **On-device**: Apple's text reader pulls the words off the pack and they
///    are matched against the bundled catalogue. No network, no description,
///    and it only recognises drugs the catalogue knows — but it always works.
///
/// Either way, the **food and drink advice comes from the catalogue, never from
/// the model**. The model is trusted to read a label that the person can hold up
/// against the photo. It is not trusted to say what is safe to eat, because it
/// would answer just as fluently if it were wrong.
@MainActor
@Observable
final class IdentifyMedicineViewModel {

    enum Source { case gemini, onDevice }

    struct Result: Equatable {
        var identification: MedicineIdentification
        var source: Source
    }

    enum Phase: Equatable {
        case idle
        case reading(String)
        case found(Result)
        case failed(String)
    }

    /// The picture. Changing it clears the last answer.
    var image: UIImage? {
        didSet { if image !== oldValue { reset() } }
    }

    private(set) var phase: Phase = .idle
    /// Why the AI was skipped, when it was meant to be.
    private(set) var aiNotice: String?
    /// Food and drink for whatever was found; loaded after the label is read.
    private(set) var food: MedicineFoodViewModel

    let consent: AIConsentPrompt

    private let ai: MedicineAIServicing
    private let ocr: PrescriptionOCRServicing
    private let drugInfo: DrugInfoServicing

    init(
        ai: MedicineAIServicing,
        drugInfo: DrugInfoServicing,
        ocr: PrescriptionOCRServicing = PrescriptionOCRService(),
        consent: AIConsentPrompt? = nil
    ) {
        self.ai = ai
        self.drugInfo = drugInfo
        self.ocr = ocr
        self.consent = consent ?? AIConsentPrompt()
        self.food = MedicineFoodViewModel(drugInfo: drugInfo)
    }

    convenience init(services: ServiceContainer) {
        self.init(ai: services.ai, drugInfo: services.drugInfo)
    }

    var canIdentify: Bool {
        guard image != nil else { return false }
        if case .reading = phase { return false }
        return true
    }

    var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    // MARK: - Identify

    func identify() async {
        guard let image else { return }
        await consent.gate(
            ai: ai,
            withAI: { [weak self] in await self?.run(image, usingAI: true) },
            onDevice: { [weak self] in await self?.run(image, usingAI: false) }
        )
    }

    private func run(_ image: UIImage, usingAI: Bool) async {
        aiNotice = nil
        phase = .reading(usingAI ? "Reading the label with Gemini..." : "Reading the label...")

        if usingAI {
            do {
                let found = try await ai.identifyMedicine(image: image)
                await finish(Result(identification: found, source: .gemini))
                return
            } catch let error as MedicineAIError {
                switch error {
                case .nothingFound(let message):
                    // A real answer — "that is not a medicine" — not a reason
                    // to try again with a weaker reader.
                    phase = .failed(message)
                    return
                default:
                    aiNotice = Self.notice(for: error)
                }
            } catch {
                aiNotice = "Gemini could not be used, so this was read on your device."
            }
            phase = .reading("Reading the label...")
        }

        await runOnDevice(image)
    }

    private func runOnDevice(_ image: UIImage) async {
        do {
            let text = try await ocr.recognizeText(in: image)
            if let found = await matchCatalogue(in: text) {
                await finish(Result(identification: found, source: .onDevice))
            } else {
                phase = .failed(
                    "Could not match this pack to a medicine MedicFood knows. Try a clearer photo of the name, or search for it in Drug-Food Interactions."
                )
            }
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Could not read that photo.")
        }
    }

    private func finish(_ result: Result) async {
        phase = .found(result)
        await loadFood(for: result.identification)
    }

    // MARK: - On-device matching

    /// Find a catalogue drug in the words printed on a pack.
    ///
    /// Exact matches only. A pack says things like "DOLO 650 Paracetamol Tablets
    /// IP", and a near-match would attach the wrong drug's advice, so each word
    /// and each cleaned-up line must equal a known name or brand to count.
    func matchCatalogue(in text: String) async -> MedicineIdentification? {
        let strength = Self.strength(in: text)

        var terms: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            terms.append(contentsOf: DrugNameNormalizer.candidates(from: line))
            terms.append(contentsOf: line.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init))
        }

        var seen = Set<String>()
        for term in terms where term.count >= 4 {
            let key = term.lowercased()
            guard seen.insert(key).inserted else { continue }

            let suggestions = await drugInfo.suggestions(for: term, limit: 5)
            guard let exact = suggestions.first(where: {
                $0.title.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else { continue }

            return MedicineIdentification(
                name: exact.title,
                genericName: exact.subtitle == nil ? nil : exact.completion,
                strength: strength,
                form: nil,
                purpose: nil
            )
        }
        return nil
    }

    /// The first thing that looks like a strength: "650 mg", "5 ml", "60,000 IU".
    static func strength(in text: String) -> String? {
        let pattern = #"\d{1,3}(?:,\d{3})*(?:\.\d+)?\s?(?:mg|mcg|µg|g|ml|iu)\b"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Food

    /// Look up food advice for whatever was found, trying the generic name
    /// first (that is what the catalogue is keyed by) and the printed name
    /// second.
    private func loadFood(for identification: MedicineIdentification) async {
        let names = [identification.genericName, identification.name].compactMap { $0 }
        food = MedicineFoodViewModel(drugInfo: drugInfo)

        for name in names {
            let probe = Medicine(name: name, dosage: identification.strength ?? "", slots: [.morning])
            await food.load(for: probe)
            if case .found = food.state { return }
            if case .failed = food.state { return }
        }
    }

    // MARK: - Hand-off to Add Medicine

    /// What to pre-fill when the user adds the medicine they just identified.
    func prefill() -> MedicinePrefill? {
        guard case .found(let result) = phase else { return nil }
        let found = result.identification
        return MedicinePrefill(
            name: found.genericName ?? found.name,
            dosage: found.strength ?? "",
            form: found.form ?? .tablet
        )
    }

    // MARK: - Helpers

    private func reset() {
        phase = .idle
        aiNotice = nil
        food = MedicineFoodViewModel(drugInfo: drugInfo)
    }

    private static func notice(for error: MedicineAIError) -> String? {
        switch error {
        case .unavailable:  nil
        case .offline:      "No internet, so this was read on your device instead of with Gemini."
        case .notEnabled:   "Gemini has not been switched on for this app yet, so this was read on your device."
        default:            "Gemini could not read that, so this was read on your device."
        }
    }
}
