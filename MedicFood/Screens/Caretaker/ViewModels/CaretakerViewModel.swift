import Foundation
import Observation

/// Drives the caretaker screen.
@MainActor
@Observable
final class CaretakerViewModel {

    private(set) var patients: [LinkedPatient] = []
    private(set) var isLoading = false
    private(set) var isLinking = false
    private(set) var errorMessage: String?

    var enteredCode = ""

    private let service: CaretakerServicing

    init(service: CaretakerServicing) {
        self.service = service
    }

    convenience init(services: ServiceContainer) {
        self.init(service: services.caretakers)
    }

    var isEmpty: Bool { !isLoading && patients.isEmpty }

    var canLink: Bool {
        enteredCode.trimmingCharacters(in: .whitespaces).count == 6 && !isLinking
    }

    /// Anyone below 70% adherence — the reason a caretaker opens this screen.
    var needingAttention: [LinkedPatient] {
        patients.filter(\.isFallingBehind)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            patients = try await service.patients()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func link() async {
        guard canLink else { return }

        isLinking = true
        errorMessage = nil
        defer { isLinking = false }

        do {
            _ = try await service.link(shareCode: enteredCode)
            enteredCode = ""
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func unlink(_ patient: LinkedPatient) async {
        do {
            try await service.unlink(patientID: patient.id)
            patients.removeAll { $0.id == patient.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
