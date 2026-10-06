import UIKit
import Vision

/// Reads text out of a prescription image.
///
/// A protocol so the ViewModel can be tested with a fake and so a server-side
/// reader can replace it later without touching any screen.
protocol PrescriptionOCRServicing: Sendable {
    func recognizeText(in image: UIImage) async throws -> String
}

enum PrescriptionOCRError: LocalizedError {
    case unreadableImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "Unable to read prescription. Try scanning it again."
        case .noTextFound:     "No text was found. Make sure the page is well lit and in focus, or type it below."
        }
    }
}

/// On-device OCR with Apple's Vision framework.
///
/// The Vision request is created, run and read entirely inside one detached
/// task, so nothing Vision-related crosses an actor boundary. Only the final
/// `String` comes back.
struct PrescriptionOCRService: PrescriptionOCRServicing {

    /// `CGImage` is immutable but not declared `Sendable`; this box says so once.
    private struct ImageBox: @unchecked Sendable {
        let cgImage: CGImage
        let orientation: CGImagePropertyOrientation
    }

    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw PrescriptionOCRError.unreadableImage }
        let box = ImageBox(cgImage: cgImage, orientation: .make(from: image.imageOrientation))

        let lines: [String] = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: box.cgImage, orientation: box.orientation, options: [:])
            try handler.perform([request])

            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PrescriptionOCRError.noTextFound }
        return text
    }
}

extension CGImagePropertyOrientation {
    static func make(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            return .up
        case .upMirrored:    return .upMirrored
        case .down:          return .down
        case .downMirrored:  return .downMirrored
        case .left:          return .left
        case .leftMirrored:  return .leftMirrored
        case .right:         return .right
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
