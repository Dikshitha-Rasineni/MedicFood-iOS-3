import Foundation
import Observation

/// Who is signed in, and the app-wide state that follows from it.
///
/// The Flutter app spread this across a handful of `SharedPreferences` keys
/// (`isLoggedIn`, `user_id`, `name_{userId}`) read directly from whichever
/// widget needed them. One object owning it means there is exactly one answer
/// to "is someone signed in", and the views react to it automatically.
@MainActor
@Observable
final class UserSession {

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserProfile)
    }

    private(set) var state: State = .loading

    var profile: UserProfile? {
        if case .signedIn(let profile) = state { return profile }
        return nil
    }

    var isSignedIn: Bool { profile != nil }

    private let defaults: UserDefaults
    private static let profileKey = "medicfood.session.profile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Restore a previous session from disk. Called by the splash screen.
    ///
    /// The artificial delay is not padding — it gives the splash a beat so the
    /// app does not flash between two screens on a fast device.
    /// `auth` is the backend's own view of who is signed in. When it keeps a
    /// session of its own (Firebase does; the mock stack does not) it is the
    /// authority, and a cached profile it disagrees with is discarded.
    ///
    /// Without this the app trusts a stale profile on disk, renders a
    /// signed-in home screen, and then every per-user read fails — leaving
    /// someone looking at an empty app with no way to sign in, because as far
    /// as the UI is concerned they already are.
    func restore(auth: AuthServicing? = nil) async {
        try? await Task.sleep(for: .milliseconds(600))

        guard let data = defaults.data(forKey: Self.profileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else {
            state = .signedOut
            return
        }

        if let auth, auth.validatesSession {
            guard let backendUserID = auth.currentUserID else {
                // The backend session is gone — signed out elsewhere, token
                // revoked, or this profile was left behind by the mock stack.
                defaults.removeObject(forKey: Self.profileKey)
                state = .signedOut
                return
            }
            // A cached profile for a different account is equally stale.
            guard backendUserID == profile.id else {
                defaults.removeObject(forKey: Self.profileKey)
                state = .signedOut
                return
            }
        }

        state = .signedIn(profile)
    }

    func signIn(_ profile: UserProfile) {
        state = .signedIn(profile)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    /// Sign in to the demo without touching any backend.
    ///
    /// Deliberately not written to disk: a demo should end when the app does.
    /// Persisting it would also be restored on a later launch *after* someone
    /// switched to the live backend, putting them in a signed-in session that
    /// Firebase knows nothing about.
    func signInToDemo(_ profile: UserProfile) {
        defaults.removeObject(forKey: Self.profileKey)
        state = .signedIn(profile)
    }

    func signOut() {
        state = .signedOut
        defaults.removeObject(forKey: Self.profileKey)
    }
}
