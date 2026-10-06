import Foundation

/// A person a caretaker is looking after.
struct LinkedPatient: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var adherenceRate: Double
    var dosesToday: Int
    var takenToday: Int
    var lastActive: Date?

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return String(parts.compactMap(\.first)).uppercased()
    }

    var isFallingBehind: Bool { adherenceRate < 0.7 }
}

/// Linking a caretaker to a patient, and reading how that patient is doing.
///
/// The link is a share code the patient reads out. That is deliberately low
/// tech — the people using this are often family members on a phone call.
@MainActor
protocol CaretakerServicing: AnyObject {
    func patients() async throws -> [LinkedPatient]
    func link(shareCode: String) async throws -> LinkedPatient
    func unlink(patientID: String) async throws
}

@MainActor
final class MockCaretakerService: CaretakerServicing {

    private var linked: [LinkedPatient] = [
        LinkedPatient(
            id: "patient-1",
            name: "Anand Kumar",
            adherenceRate: 0.92,
            dosesToday: 4,
            takenToday: 3,
            lastActive: Calendar.current.date(byAdding: .hour, value: -2, to: .now)
        ),
        LinkedPatient(
            id: "patient-2",
            name: "Lakshmi Iyer",
            adherenceRate: 0.61,
            dosesToday: 3,
            takenToday: 1,
            lastActive: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        ),
    ]

    func patients() async throws -> [LinkedPatient] {
        try await Task.sleep(for: .milliseconds(300))
        // Whoever needs attention first goes to the top.
        return linked.sorted { $0.adherenceRate < $1.adherenceRate }
    }

    func link(shareCode: String) async throws -> LinkedPatient {
        try await Task.sleep(for: .milliseconds(500))

        let code = shareCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6 else {
            throw APIError.server(status: 400, message: "A share code is 6 characters.")
        }
        guard !linked.contains(where: { $0.id == "patient-\(code)" }) else {
            throw APIError.server(status: 409, message: "You are already linked to that person.")
        }

        let patient = LinkedPatient(
            id: "patient-\(code)",
            name: "New patient (\(code))",
            adherenceRate: 1.0,
            dosesToday: 0,
            takenToday: 0,
            lastActive: .now
        )
        linked.append(patient)
        return patient
    }

    func unlink(patientID: String) async throws {
        linked.removeAll { $0.id == patientID }
    }
}
