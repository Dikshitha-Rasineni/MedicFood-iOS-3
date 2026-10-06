import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Email/password auth against the same Firebase project the Android app uses,
/// so an account created on either platform signs in on the other.
///
/// **Google Sign-In is not handled here.** The iOS app is registered with it
/// enabled (`IS_SIGNIN_ENABLED` in `GoogleService-Info.plist`) and Android
/// offers it, so accounts created that way have *no password* and will fail
/// here with `.wrongPassword`. `signIn` detects that case and says so plainly
/// rather than letting the user retype a password they never set.
@MainActor
final class FirebaseAuthService: AuthServicing {

    var validatesSession: Bool { true }

    var currentUserID: String? { Auth.auth().currentUser?.uid }

    func signIn(email: String, password: String) async throws -> UserProfile {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return try await profile(for: result.user)
        } catch {
            throw Self.friendlyError(error, email: email)
        }
    }

    func signUp(name: String, email: String, password: String) async throws -> UserProfile {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // Firebase stores a display name on the account; the Android app
            // reads the name off the Firestore user document instead. Write
            // both, so neither platform shows a blank name.
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()

            var profile = UserProfile(id: result.user.uid, name: name, email: email)
            profile.shareCode = Self.makeShareCode()

            try await FirestoreClient.userDocument(result.user.uid).setData(
                FirestoreSchema.userDocument(for: profile, shareCode: profile.shareCode)
                    .merging(["createdAt": FieldValue.serverTimestamp()]) { current, _ in current },
                merge: true
            )
            return profile
        } catch {
            throw Self.friendlyError(error, email: email)
        }
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }

    // MARK: - Profile

    /// Read the Firestore user document, falling back to what the auth record
    /// knows. A user created on Android before the document write existed can
    /// genuinely have no `users/{uid}` document.
    private func profile(for user: User) async throws -> UserProfile {
        let reference = FirestoreClient.userDocument(user.uid)
        let snapshot = try? await reference.getDocument()
        let fields = FirestoreClient.normalised(snapshot?.data())

        var profile = FirestoreSchema.userProfile(from: fields, uid: user.uid)
            ?? UserProfile(id: user.uid, name: user.displayName ?? "", email: user.email ?? "")

        if profile.name.isEmpty {
            profile.name = user.displayName
                ?? user.email?.components(separatedBy: "@").first
                ?? "There"
        }
        if profile.email.isEmpty { profile.email = user.email ?? "" }
        profile.shareCode = fields["shareCode"] as? String

        // A patient cannot be linked to without a share code, and accounts
        // predating the feature do not have one. Mint it on first sign-in
        // rather than making the user go looking for a button.
        if profile.shareCode == nil {
            let code = Self.makeShareCode()
            profile.shareCode = code
            try? await reference.setData(["shareCode": code], merge: true)
        }
        return profile
    }

    /// Six characters, read aloud over a phone call — so no `0`/`O`, `1`/`I`.
    static func makeShareCode() -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Errors

    /// Firebase's own messages leak implementation detail ("The supplied auth
    /// credential is malformed or has expired"). These are what the user sees.
    private static func friendlyError(_ error: Error, email: String) -> Error {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .wrongPassword, .invalidCredential:
            // The most likely cause on this project: the account exists but was
            // created with Google Sign-In, so it has no password at all.
            return AuthFailure(
                "That password did not match. If you created this account with Google on the Android app, it has no password — sign in with Google instead."
            )
        case .userNotFound:
            return AuthFailure("No account found for \(email).")
        case .emailAlreadyInUse:
            return AuthFailure("An account already exists for \(email). Sign in instead.")
        case .weakPassword:
            return AuthFailure("That password is too short. Use at least six characters.")
        case .invalidEmail:
            return AuthFailure("That does not look like an email address.")
        case .networkError:
            return AuthFailure("Could not reach the server. Check your connection and try again.")
        case .tooManyRequests:
            return AuthFailure("Too many attempts. Wait a moment and try again.")
        default:
            return error
        }
    }
}

/// A message already fit to show a user.
struct AuthFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
