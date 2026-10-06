import Foundation

/// Fetches domain types over HTTP.
///
/// This is the layer that knows a `Medicine` from a `DoseRecord`. It leans on
/// `HTTPRequesting` for the transport, so it can be tested against a fake
/// requester with no network involved.
struct APIService: Sendable {

    private let requester: HTTPRequesting
    private let decoder: JSONDecoder

    init(requester: HTTPRequesting = HTTPRequestManager()) {
        self.requester = requester

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    /// Send and decode into `T`.
    func fetch<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type = T.self) async throws -> T {
        let data = try await requester.send(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Send and ignore the body, for calls whose only meaningful result is
    /// "it worked".
    func perform(_ endpoint: APIEndpoint) async throws {
        _ = try await requester.send(endpoint)
    }
}

/// The envelope the backend wraps every response in.
///
/// Mirrors the `ResponseModel` in the SmartWaste project: a `success` flag, an
/// optional message, and the payload.
struct ResponseModel<T: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let data: T?
}
