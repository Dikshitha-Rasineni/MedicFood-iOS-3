import Foundation

/// Anything that can go wrong on the wire, in terms a screen can act on.
///
/// The Flutter code caught errors and `print`ed them — 329 `try`/`catch`
/// blocks, many swallowing the failure — so a request that failed looked
/// identical to one that returned nothing. Typed errors mean the ViewModel can
/// tell "you are offline" from "that password is wrong".
enum APIError: LocalizedError, Equatable {
    case invalidURL
    case notConnected
    case timedOut
    case unauthorized
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:    "Could not build that request."
        case .notConnected:  "You appear to be offline. Check your connection and try again."
        case .timedOut:      "The server took too long to respond."
        case .unauthorized:  "Your session has expired. Please sign in again."
        case .notFound:      "That could not be found."
        case .server(let status, let message): message ?? "The server returned an error (\(status))."
        case .decoding:      "The server sent something unexpected."
        case .unknown(let message): message
        }
    }

    /// Whether retrying the same request could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .notConnected, .timedOut: true
        case .server(let status, _): status >= 500
        default: false
        }
    }
}

/// The base HTTP wrapper: builds a `URLRequest`, sends it, and maps the
/// response into either `Data` or an `APIError`.
///
/// It knows nothing about medicines or adherence. That separation is the whole
/// point — `APIService` above it knows the domain, this knows HTTP, and
/// neither needs to change when the other does.
protocol HTTPRequesting: Sendable {
    func send(_ endpoint: APIEndpoint) async throws -> Data
}

struct HTTPRequestManager: HTTPRequesting {

    private let configuration: APIConfiguration
    private let session: URLSession

    init(configuration: APIConfiguration = .default, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func send(_ endpoint: APIEndpoint) async throws -> Data {
        let request = try buildRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw map(error)
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown("No HTTP response.")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(status: http.statusCode, message: serverMessage(from: data))
        }
    }

    /// Assemble path, query, method, headers and body into one request.
    private func buildRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent(endpoint.path)

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = endpoint.queryItems

        guard let finalURL = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: finalURL, timeoutInterval: configuration.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.allHTTPHeaderFields = configuration.defaultHeaders

        do {
            request.httpBody = try endpoint.body()
        } catch {
            throw APIError.decoding("Could not encode the request body.")
        }

        return request
    }

    /// Pull a human-readable message out of an error response, if there is one.
    private func serverMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            let message: String?
            let error: String?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.message ?? envelope.error
    }

    private func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: .notConnected
        case .timedOut: .timedOut
        case .badURL, .unsupportedURL: .invalidURL
        default: .unknown(error.localizedDescription)
        }
    }
}
