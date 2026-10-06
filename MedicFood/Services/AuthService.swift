import Foundation

/// Signing in and out.
///
/// Declared as a protocol so the app can run on mock data today and switch to
/// Firebase later by changing one line in `ServiceContainer` — no ViewModel
/// and no view changes.
@MainActor
protocol AuthServicing: AnyObject {
    func signIn(email: String, password: String) async throws -> UserProfile
    func signUp(name: String, email: String, password: String) async throws -> UserProfile
    func signOut() async throws

    /// Send a password-reset email. Without this, a forgotten password is a
    /// permanently locked account — there is no other way back in.
    func sendPasswordReset(to email: String) async throws

    /// Whether this service keeps its own session that the cached profile must
    /// agree with. False for the mock stack, which has no backend to disagree
    /// with.
    var validatesSession: Bool { get }

    /// The user the backend itself considers signed in.
    var currentUserID: String? { get }
}

extension AuthServicing {
    // Defaults so the mock stack — and any test double — is unaffected.
    var validatesSession: Bool { false }
    var currentUserID: String? { nil }

    /// The mock stack has no mail to send; it succeeds so the UI flow is
    /// exercisable on sample data.
    func sendPasswordReset(to email: String) async throws {}
}

/// In-memory auth for development and tests.
///
/// Accepts any well-formed email with a password of 6+ characters, so the app
/// is usable in the simulator with no backend. It still *fails* on a bad
/// password, so the error path is exercisable.
@MainActor
final class MockAuthService: AuthServicing {

    /// Simulated latency, so loading states are visible during development.
    var latency: Duration = .milliseconds(700)

    func signIn(email: String, password: String) async throws -> UserProfile {
        try await Task.sleep(for: latency)

        guard password.count >= 6 else {
            throw APIError.server(status: 401, message: "Incorrect email or password.")
        }

        return UserProfile(
            id: UUID().uuidString,
            name: Self.name(fromEmail: email),
            email: email,
            shareCode: Self.makeShareCode()
        )
    }

    func signUp(name: String, email: String, password: String) async throws -> UserProfile {
        try await Task.sleep(for: latency)

        guard password.count >= 6 else {
            throw APIError.server(status: 400, message: "Password must be at least 6 characters.")
        }

        return UserProfile(
            id: UUID().uuidString,
            name: name,
            email: email,
            shareCode: Self.makeShareCode()
        )
    }

    func signOut() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    /// "priya.sharma@example.com" -> "Priya Sharma"
    private static func name(fromEmail email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let words = local.split(whereSeparator: { ".-_".contains($0) })
        guard !words.isEmpty else { return "User" }
        return words.map { $0.capitalized }.joined(separator: " ")
    }

    /// Six-character code a caretaker types to link to this patient.
    /// Excludes look-alike characters (0/O, 1/I) because these get read aloud.
    private static func makeShareCode() -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
