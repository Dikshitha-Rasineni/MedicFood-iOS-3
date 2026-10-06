import UIKit
import Observation

/// What the scanner hands to the Add Medicine form for one medicine.
struct MedicinePrefill: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var dosage = ""
    var shorthand = ""
    var form: MedicineForm = .tablet
    var food: FoodInstruction = .anyTime
    var durationText = ""
    var prescriptionImage: UIImage?
    var voiceFileName: String?

    static func == (lhs: MedicinePrefill, rhs: MedicinePrefill) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Scan or pick a prescription, read it, review what was found, then continue
/// into the Add Medicine form for each medicine.
///
/// Flow: image → OCR (`PrescriptionOCRService`) → text → `PrescriptionParser`
/// → reviewable drafts → Add Medicine details. Nothing is saved here; the Add
/// Medicine form owns validation and saving.
@MainActor
@Observable
final class PrescriptionScannerViewModel {

    /// One medicine the user is reviewing.
    struct DraftMedicine: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var dosage: String
        var shorthand: String
        var form: MedicineForm = .tablet
        var food: FoodInstruction = .anyTime
        var durationText: String = ""
        var isSelected: Bool = true

        var slots: [DoseSlot] { PrescriptionParser.slots(from: shorthand) }
        var summary: String { slots.map(\.displayName).joined(separator: " & ") }
    }

    /// The prescription picture. Changing it clears any earlier reading.
    var image: UIImage? {
        didSet { if image !== oldValue { resetReading() } }
    }

    /// Editable: the user can fix OCR mistakes, or type a prescription instead.
    var extractedText = ""
    var drafts: [DraftMedicine] = []

    private(set) var isProcessing = false
    private(set) var processingMessage = ""
    private(set) var errorMessage: String?
    private(set) var hasRead = false

    let voice = VoiceController()

    /// Speaking a prescription instead of photographing it.
    let dictation = DictationController()

    /// Asks before anything is sent to Gemini.
    let consent: AIConsentPrompt

    /// Who read the current drafts, so the screen can say so. Whatever read
    /// them, the person is still asked to check every one.
    enum ReadSource { case gemini, onDevice }
    private(set) var readSource: ReadSource?

    /// Why the AI was not used, when it was meant to be — shown as a note, not
    /// as an error, because the on-device reader still produced a result.
    private(set) var aiNotice: String?

    /// The medicine currently open in Add Medicine, and the queue behind it.
    var addSeed: MedicinePrefill?
    private(set) var isFinished = false
    private var queue: [DraftMedicine] = []
    private var queueIndex = 0

    private let ocr: PrescriptionOCRServicing
    private let ai: MedicineAIServicing

    init(
        ocr: PrescriptionOCRServicing = PrescriptionOCRService(),
        ai: MedicineAIServicing? = nil,
        consent: AIConsentPrompt? = nil
    ) {
        self.ocr = ocr
        self.ai = ai ?? UnavailableMedicineAI()
        self.consent = consent ?? AIConsentPrompt()

        // When speaking stops, what was said becomes medicines to review.
        dictation.onFinished = { [weak self] transcript in
            guard let self else { return }
            Task { await self.finishDictation(transcript) }
        }
    }

    convenience init(services: ServiceContainer) {
        self.init(ai: services.ai)
    }

    /// Whether the screen should offer to read by voice and say AI is involved.
    var aiAvailable: Bool { ai.isAvailable }

    var canRead: Bool { image != nil && !isProcessing }
    var selectedCount: Int { drafts.filter(\.isSelected).count }
    var canContinue: Bool { selectedCount > 0 && !isProcessing }

    // MARK: Reading

    func readPrescription() async {
        guard let image else { return }
        await consent.gate(
            ai: ai,
            withAI: { [weak self] in await self?.read(image, usingAI: true) },
            onDevice: { [weak self] in await self?.read(image, usingAI: false) }
        )
    }

    private func read(_ image: UIImage, usingAI: Bool) async {
        errorMessage = nil
        aiNotice = nil
        isProcessing = true
        processingMessage = usingAI ? "Reading with Gemini..." : "Reading prescription..."
        defer { isProcessing = false }

        if usingAI {
            do {
                let reading = try await ai.readPrescription(image: image)
                extractedText = reading.text
                drafts = reading.medicines.map(Self.draft(from:))
                readSource = .gemini
                hasRead = true
                if drafts.isEmpty { errorMessage = "No medicines found. Edit the text above and try again." }
                return
            } catch {
                // Not the end: the on-device reader is still there. Say why the
                // AI was skipped, then carry on.
                aiNotice = Self.notice(for: error)
                processingMessage = "Reading prescription..."
            }
        }

        do {
            let text = try await ocr.recognizeText(in: image)
            extractedText = text
            processingMessage = "Extracting medicines..."
            parse()
            readSource = .onDevice
            hasRead = true
        } catch {
            hasRead = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to read prescription."
        }
    }

    // MARK: Text and speech

    /// "Extract medicines" — from typed text, or from what was just said.
    func extractFromText() async {
        let text = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        await consent.gate(
            ai: ai,
            withAI: { [weak self] in await self?.extract(text, usingAI: true) },
            onDevice: { [weak self] in await self?.extract(text, usingAI: false) }
        )
    }

    private func extract(_ text: String, usingAI: Bool) async {
        errorMessage = nil
        aiNotice = nil

        if usingAI {
            isProcessing = true
            processingMessage = "Finding medicines with Gemini..."
            defer { isProcessing = false }
            do {
                let medicines = try await ai.readDictation(text)
                drafts = medicines.map(Self.draft(from:))
                readSource = .gemini
                hasRead = true
                return
            } catch {
                aiNotice = Self.notice(for: error)
            }
        }

        parse()
        readSource = .onDevice
        hasRead = true
    }

    /// Start or stop listening.
    func toggleDictation() async {
        errorMessage = nil
        await dictation.toggle()
    }

    private func finishDictation(_ transcript: String) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // The words go into the editable box first, so a misheard drug name can
        // be fixed before anything is extracted from it.
        extractedText = text
        hasRead = true
        await extractFromText()
    }

    /// A reason the AI was skipped, in words for the person. `nil` when the AI
    /// was simply not there, which needs no explaining.
    private static func notice(for error: Error) -> String? {
        guard let error = error as? MedicineAIError else {
            return "Gemini could not be used, so this was read on your device."
        }
        switch error {
        case .unavailable:
            return nil
        case .offline:
            return "No internet, so this was read on your device instead of with Gemini."
        case .notEnabled:
            return "Gemini has not been switched on for this app yet, so this was read on your device."
        default:
            return "Gemini could not read that, so this was read on your device."
        }
    }

    static func draft(from medicine: AIMedicine) -> DraftMedicine {
        DraftMedicine(
            name: medicine.name,
            dosage: medicine.dosage,
            shorthand: medicine.timing,
            form: medicine.form,
            food: medicine.food,
            durationText: medicine.duration
        )
    }

    /// Turn the (possibly edited) text into reviewable drafts.
    func parse() {
        let lines = Self.lines(from: extractedText)
        let medicineLines = lines.filter(Self.looksLikeMedicine)
        // Typed text may be bare names; scanned text is filtered to likely lines.
        let chosen = medicineLines.isEmpty ? lines : medicineLines
        drafts = chosen.map(Self.draft(from:))
        if drafts.isEmpty {
            errorMessage = "No medicines found. Edit the text above and try again."
        } else if errorMessage?.hasPrefix("No medicines") == true {
            errorMessage = nil
        }
    }

    func removeImage() { image = nil }

    /// Lets the user type a prescription when there is nothing to scan.
    func startTyping() { hasRead = true }

    private func resetReading() {
        drafts = []
        extractedText = ""
        errorMessage = nil
        aiNotice = nil
        readSource = nil
        hasRead = false
    }

    // MARK: Continue into Add Medicine

    func beginAddFlow() {
        queue = drafts.filter(\.isSelected)
        queueIndex = 0
        isFinished = false
        addSeed = queue.first.map(seed(from:))
    }

    /// Called when one medicine has been saved; opens the next or finishes.
    func advance() {
        queueIndex += 1
        addSeed = nil
        guard queueIndex < queue.count else {
            isFinished = true
            return
        }
        let next = queue[queueIndex]
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            addSeed = seed(from: next)
        }
    }

    private func seed(from draft: DraftMedicine) -> MedicinePrefill {
        MedicinePrefill(
            name: draft.name,
            dosage: draft.dosage,
            shorthand: draft.shorthand,
            form: draft.form,
            food: draft.food,
            durationText: draft.durationText,
            prescriptionImage: image,
            voiceFileName: voice.fileName
        )
    }

    // MARK: Parsing helpers

    static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let dosagePattern = #"\d+(?:[.,]\d+)?\s?(?:mg|mcg|ml|iu|g|%)(?![A-Za-z])"#

    static func looksLikeMedicine(_ line: String) -> Bool {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        return line.range(of: dosagePattern, options: options) != nil
            || line.range(of: #"^(tab|cap|syp|inj)\b"#, options: options) != nil
            || line.range(of: #"\d+-\d+-\d+"#, options: .regularExpression) != nil
    }

    /// Split one line into name, dosage, form, timing, food and duration.
    static func draft(from rawLine: String) -> DraftMedicine {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]

        var form: MedicineForm?
        if let range = line.range(of: #"^(tablet|tab|capsule|cap|syrup|syp|injection|inj)s?\.?\s+"#, options: options) {
            form = PrescriptionParser.form(from: String(line[range]))
            line.removeSubrange(range)
        }

        var dosage = ""
        if let range = line.range(of: dosagePattern, options: options) {
            dosage = String(line[range])
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: #"(\d)([A-Za-z%])"#, with: "$1 $2", options: .regularExpression)
            line.removeSubrange(range)
        }

        var duration = ""
        if let range = line.range(of: #"(?:x\s*)?\d+\s?(?:days?|weeks?|wks?)\b"#, options: options) {
            duration = String(line[range])
                .replacingOccurrences(of: #"^x\s*"#, with: "", options: options)
            line.removeSubrange(range)
        }

        let stopWords: Set<String> = [
            "after", "before", "with", "empty", "food", "daily", "morning", "night", "afternoon",
            "evening", "twice", "thrice", "once", "at", "for", "x", "stomach"
        ]
        var name: [String] = []
        var timing: [String] = []
        for token in line.split(whereSeparator: \.isWhitespace).map(String.init) {
            let isNotation = token.range(of: #"^\d+-\d+-\d+"#, options: .regularExpression) != nil
            let isTiming = isNotation
                || PrescriptionParser.doseCount(from: token) != nil
                || stopWords.contains(token.lowercased())
            if timing.isEmpty && !isTiming {
                name.append(token.trimmingCharacters(in: .punctuationCharacters))
            } else {
                timing.append(token)
            }
        }

        let shorthand = timing.joined(separator: " ")
        return DraftMedicine(
            name: name.filter { !$0.isEmpty }.joined(separator: " "),
            dosage: dosage,
            shorthand: shorthand,
            form: form ?? PrescriptionParser.form(from: rawLine),
            food: PrescriptionParser.foodInstruction(from: shorthand),
            durationText: duration
        )
    }
}
