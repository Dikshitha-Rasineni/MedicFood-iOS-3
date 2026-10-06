import Foundation

/// The signed-in user.
struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var email: String

    /// Code a caretaker enters to link to this patient.
    var shareCode: String?

    var caretakerIDs: [String] = []
    var patientIDs: [String] = []

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// Credentials for the sign-in form. Kept as a type so the ViewModel can
/// validate it without reaching into text fields.
struct Credentials: Hashable, Sendable {
    var email: String = ""
    var password: String = ""

    var isValid: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    /// Nil when valid; otherwise the reason, ready to show.
    var validationMessage: String? {
        if email.isEmpty || password.isEmpty { return "Enter your email and password." }
        if !email.contains("@") || !email.contains(".") { return "That does not look like an email address." }
        if password.count < 6 { return "Password must be at least 6 characters." }
        return nil
    }
}
