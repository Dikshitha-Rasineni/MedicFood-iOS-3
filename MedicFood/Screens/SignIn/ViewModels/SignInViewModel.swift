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

    var mode: Mode = .signIn
    var name = ""
    var credentials = Credentials()

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let auth: AuthServicing

    init(auth: AuthServicing) {
        self.auth = auth
    }

    convenience init(services: ServiceContainer) {
        self.init(auth: services.auth)
    }

    /// Whether the button should be enabled.
    var canSubmit: Bool {
        guard !isSubmitting, credentials.isValid else { return false }
        if mode == .signUp { return !name.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
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
            errorMessage = credentials.validationMessage
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
