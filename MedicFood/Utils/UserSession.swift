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
    func restore() async {
        try? await Task.sleep(for: .milliseconds(600))

        if let data = defaults.data(forKey: Self.profileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            state = .signedIn(profile)
        } else {
            state = .signedOut
        }
    }

    func signIn(_ profile: UserProfile) {
        state = .signedIn(profile)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    func signOut() {
        state = .signedOut
        defaults.removeObject(forKey: Self.profileKey)
    }
}
