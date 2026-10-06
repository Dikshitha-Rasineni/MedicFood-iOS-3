import Foundation

/// Which backend the app talks to.
///
/// Selecting an environment is a build-time or debug-menu concern, never
/// something a screen decides — so it lives here and nowhere else.
enum APIEnvironment: String, CaseIterable, Sendable {
    case development
    case staging
    case production

    var baseURL: URL {
        switch self {
        case .development: URL(string: "https://dev-api.medicfood.app/v1")!
        case .staging:     URL(string: "https://staging-api.medicfood.app/v1")!
        case .production:  URL(string: "https://api.medicfood.app/v1")!
        }
    }

    var displayName: String { rawValue.capitalized }
}

/// Network configuration: environment, timeouts, and the default headers every
/// request carries.
struct APIConfiguration: Sendable {

    let environment: APIEnvironment
    let timeout: TimeInterval
    /// Bearer token, when signed in.
    var authToken: String?

    /// Debug builds hit development; release builds hit production. There is
    /// no way to ship a build pointed at a dev server by accident.
    static var `default`: APIConfiguration {
        #if DEBUG
        APIConfiguration(environment: .development, timeout: 30)
        #else
        APIConfiguration(environment: .production, timeout: 30)
        #endif
    }

    init(environment: APIEnvironment, timeout: TimeInterval = 30, authToken: String? = nil) {
        self.environment = environment
        self.timeout = timeout
        self.authToken = authToken
    }

    var baseURL: URL { environment.baseURL }

    var defaultHeaders: [String: String] {
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]
        if let authToken {
            headers["Authorization"] = "Bearer \(authToken)"
        }
        return headers
    }
}

/// Public drug-information APIs. These need no key and are not part of the
/// app's own backend, so they are kept separate from `APIEnvironment`.
enum PublicAPI {
    /// Name → RxCUI resolution and fuzzy matching.
    static let rxNorm = URL(string: "https://rxnav.nlm.nih.gov/REST")!
    /// Drug label data.
    static let openFDA = URL(string: "https://api.fda.gov/drug/label.json")!
}
