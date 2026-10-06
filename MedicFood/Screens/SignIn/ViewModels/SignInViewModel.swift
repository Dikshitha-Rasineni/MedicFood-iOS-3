import Foundation
import Observation

/// Drives the sign-in and sign-up form.
@MainActor
@Observable
final class SignInViewModel {

    enum Mode: String, CaseIterable {
        case signIn, signUp

        var title: String { self == .signIn ? "Sign in" : "Create account" }
        var callToAction: String { self == .signIn ? "Sign in" : "Create account" }
        var switchPrompt: String {
            self == .signIn ? "New here? Create an account" : "Already have an account? Sign in"
        }
    }

    var mode: Mode
    var name = ""
    var credentials = Credentials()
    /// Only used when creating an account, where a typo in a password you
    /// cannot see locks you out of your own medicines.
    var confirmPassword = ""

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let auth: AuthServicing

    init(auth: AuthServicing, mode: Mode = .signIn) {
        self.auth = auth
        self.mode = mode
    }

    convenience init(services: ServiceContainer, mode: Mode = .signIn) {
        self.init(auth: services.auth, mode: mode)
    }

    /// Whether the button should be enabled.
    var canSubmit: Bool {
        guard !isSubmitting, credentials.isValid else { return false }
        if mode == .signUp {
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
                && confirmPassword == credentials.password
        }
        return true
    }

    /// Shown under the confirm field as the user types, rather than only after
    /// they press the button.
    var passwordMismatch: Bool {
        mode == .signUp && !confirmPassword.isEmpty && confirmPassword != credentials.password
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
    }

    /// Attempts sign-in and returns the profile on success.
    ///
    /// The ViewModel does not navigate — it hands the result back and the view
    /// decides. That is the MVVM contract, and it is why this method is
    /// testable without a UI.
    func submit() async -> UserProfile? {
        guard canSubmit else {
            errorMessage = mode == .signUp && confirmPassword != credentials.password
                ? "Those passwords do not match."
                : credentials.validationMessage
            return nil
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                return try await auth.signIn(
                    email: credentials.email,
                    password: credentials.password
                )
            case .signUp:
                return try await auth.signUp(
                    name: name.trimmingCharacters(in: .whitespaces),
                    email: credentials.email,
                    password: credentials.password
                )
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
