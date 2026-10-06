import UIKit

/// What an AI model is asked to do in this app, and what it hands back.
///
/// Three jobs, all of them *reading* rather than *advising*:
///
/// - read a photographed prescription into medicines,
/// - turn a spoken or typed description into medicines,
/// - read the label on a medicine pack.
///
/// Nothing here gives food or dosing advice. That comes from the bundled
/// catalogue, which is a fixed list that can be checked. A model asked "what
/// should I avoid with this drug" will answer fluently whether or not it is
/// right; a model asked "what does this label say" can be compared against the
/// photo by the person holding it.
///
/// Everything returned is a **draft**. It is shown to the user to correct and
/// confirm, and nothing is saved by this layer.

// MARK: - Results

/// One medicine as read by a model.
struct AIMedicine: Equatable, Sendable {
    var name: String
    var dosage: String = ""
    /// Exactly as written or said — `1-0-1`, `BD`, "morning and night" — so the
    /// existing `PrescriptionParser` turns it into dose slots. Interpreting it
    /// here as well would mean two parsers that can disagree.
    var timing: String = ""
    var form: MedicineForm = .tablet
    var food: FoodInstruction = .anyTime
    var duration: String = ""
}

/// A prescription photo, read.
struct PrescriptionReading: Equatable, Sendable {
    /// What the model transcribed. Shown in an editable box, so a misread word
    /// can be fixed and the medicines re-extracted.
    var text: String
    var medicines: [AIMedicine]
}

/// The label on a medicine pack, read.
struct MedicineIdentification: Equatable, Sendable {
    var name: String
    var genericName: String?
    var strength: String?
    var form: MedicineForm?
    /// A one-line general description. Written by the model, not looked up, and
    /// shown as such.
    var purpose: String?
}

// MARK: - Errors

enum MedicineAIError: LocalizedError, Equatable {
    /// No model is configured, or the user has not allowed it. The caller falls
    /// back to the on-device path rather than showing this.
    case unavailable
    /// The picture or text did not contain what was asked for.
    case nothingFound(String)
    /// The model's safety filters declined the content.
    case blocked
    case offline
    case quotaExceeded
    /// Gemini through Firebase is not switched on for the project.
    case notEnabled
    case malformedResponse
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "AI reading is not available right now."
        case .nothingFound(let what):
            what
        case .blocked:
            "The AI could not process that image. Try a clearer photo."
        case .offline:
            "No internet connection. Check your connection and try again."
        case .quotaExceeded:
            "The AI service is busy right now. Try again in a minute."
        case .notEnabled:
            "AI reading has not been switched on for this app yet."
        case .malformedResponse:
            "The AI gave an answer the app could not understand. Try again."
        case .failed(let message):
            message
        }
    }
}

// MARK: - Service

@MainActor
protocol MedicineAIServicing: AnyObject {
    /// Whether a model is wired up. When `false` the app uses its on-device
    /// reader and never mentions AI.
    var isAvailable: Bool { get }

    func readPrescription(image: UIImage) async throws -> PrescriptionReading
    func readDictation(_ transcript: String) async throws -> [AIMedicine]
    func identifyMedicine(image: UIImage) async throws -> MedicineIdentification
}

/// Used when no model is configured — the sample-data stack without Firebase,
/// or a clone with no `GoogleService-Info.plist`. Every call throws
/// `.unavailable`, which callers treat as "use the on-device reader".
@MainActor
final class UnavailableMedicineAI: MedicineAIServicing {
    var isAvailable: Bool { false }

    func readPrescription(image: UIImage) async throws -> PrescriptionReading { throw MedicineAIError.unavailable }
    func readDictation(_ transcript: String) async throws -> [AIMedicine] { throw MedicineAIError.unavailable }
    func identifyMedicine(image: UIImage) async throws -> MedicineIdentification { throw MedicineAIError.unavailable }
}

// MARK: - Reading the model's answer

/// Turns a model's JSON into the types above.
///
/// The model is asked for JSON in a fixed shape, but its output is still
/// untrusted input: it can be malformed, it can be empty, and it can contain
/// text that came from the photographed page — which may itself contain
/// instructions. So every field is trimmed, bounded and mapped onto a closed
/// vocabulary here, and anything that does not fit is dropped rather than
/// passed on.
enum AIResponseParser {

    private struct Medicines: Decodable {
        var text: String?
        var medicines: [RawMedicine]?
    }

    private struct RawMedicine: Decodable {
        var name: String?
        var dosage: String?
        var timing: String?
        var form: String?
        var food: String?
        var duration: String?
    }

    private struct RawIdentification: Decodable {
        var isMedicine: Bool?
        var name: String?
        var genericName: String?
        var strength: String?
        var form: String?
        var purpose: String?
    }

    /// More than this from one prescription is a runaway, not a prescription.
    static let maxMedicines = 20

    // MARK: Entry points

    static func prescription(from response: String) throws -> PrescriptionReading {
        let decoded: Medicines = try decode(response)
        let medicines = (decoded.medicines ?? []).compactMap(medicine(from:))
        return PrescriptionReading(
            text: clean(decoded.text, limit: 4000),
            medicines: Array(medicines.prefix(maxMedicines))
        )
    }

    static func dictation(from response: String) throws -> [AIMedicine] {
        let decoded: Medicines = try decode(response)
        return Array((decoded.medicines ?? []).compactMap(medicine(from:)).prefix(maxMedicines))
    }

    static func identification(from response: String) throws -> MedicineIdentification {
        let raw: RawIdentification = try decode(response)

        // The model is told to say so when the picture is not a medicine, and
        // that is a result, not a failure.
        guard raw.isMedicine != false else {
            throw MedicineAIError.nothingFound("That does not look like a medicine. Try the pack or strip.")
        }

        let name = clean(raw.name, limit: 80)
        guard !name.isEmpty else {
            throw MedicineAIError.nothingFound("Could not read a medicine name. Try a clearer photo of the label.")
        }

        return MedicineIdentification(
            name: name,
            genericName: nonEmpty(clean(raw.genericName, limit: 80)),
            strength: nonEmpty(clean(raw.strength, limit: 40)),
            form: raw.form.flatMap(form(from:)),
            purpose: nonEmpty(clean(raw.purpose, limit: 300))
        )
    }

    // MARK: Mapping

    private static func medicine(from raw: RawMedicine) -> AIMedicine? {
        let name = clean(raw.name, limit: 80)
        // A medicine with no name cannot be reminded about or looked up.
        guard !name.isEmpty else { return nil }

        return AIMedicine(
            name: name,
            dosage: clean(raw.dosage, limit: 40),
            timing: clean(raw.timing, limit: 60),
            form: raw.form.flatMap(form(from:)) ?? .tablet,
            food: raw.food.flatMap(food(from:)) ?? .anyTime,
            duration: clean(raw.duration, limit: 40)
        )
    }

    /// The model is given the exact words, but is not trusted to use them.
    private static func form(from text: String) -> MedicineForm? {
        if let exact = MedicineForm(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased()) {
            return exact
        }
        let guess = PrescriptionParser.form(from: text)
        return guess == .other ? nil : guess
    }

    private static func food(from text: String) -> FoodInstruction? {
        if let exact = FoodInstruction(rawValue: text.trimmingCharacters(in: .whitespaces)) {
            return exact
        }
        let guess = PrescriptionParser.foodInstruction(from: text)
        return guess == .anyTime ? nil : guess
    }

    // MARK: Cleaning

    /// Trim, collapse whitespace, strip control characters, bound the length.
    static func clean(_ text: String?, limit: Int) -> String {
        guard let text else { return "" }
        let scalars = text.unicodeScalars.filter { scalar in
            scalar == "\n" || !CharacterSet.controlCharacters.contains(scalar)
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    // MARK: Decoding

    /// Decode, tolerating a model that wraps its JSON in a code fence or a
    /// sentence despite being told not to.
    private static func decode<T: Decodable>(_ response: String) throws -> T {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              start < end,
              let data = String(response[start...end]).data(using: .utf8)
        else { throw MedicineAIError.malformedResponse }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MedicineAIError.malformedResponse
        }
    }
}
