import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Every call the app can make, as one enum.
///
/// The point of listing them in a single type is that the set of things the
/// app asks the server for is *readable* — you can see the whole API surface
/// without grepping for `URLRequest`. A screen can only reach the network by
/// naming a case here.
enum APIEndpoint: Sendable {
    // Auth
    case signIn(email: String, password: String)
    case signUp(name: String, email: String, password: String)
    case signOut

    // Medicines
    case medicines
    case medicine(id: UUID)
    case createMedicine(Medicine)
    case updateMedicine(Medicine)
    case deleteMedicine(id: UUID)

    // Adherence
    case doseRecords(from: Date, to: Date)
    case recordDose(DoseRecord)

    // Caretaker
    case linkCaretaker(shareCode: String)
    case patients

    var path: String {
        switch self {
        case .signIn:  "/auth/sign-in"
        case .signUp:  "/auth/sign-up"
        case .signOut: "/auth/sign-out"

        case .medicines, .createMedicine: "/medicines"
        case .medicine(let id), .deleteMedicine(let id): "/medicines/\(id.uuidString)"
        case .updateMedicine(let medicine): "/medicines/\(medicine.id.uuidString)"

        case .doseRecords: "/adherence/records"
        case .recordDose:  "/adherence/records"

        case .linkCaretaker: "/caretakers/link"
        case .patients:      "/caretakers/patients"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .signIn, .signUp, .signOut, .createMedicine, .recordDose, .linkCaretaker:
            .post
        case .medicines, .medicine, .doseRecords, .patients:
            .get
        case .updateMedicine:
            .put
        case .deleteMedicine:
            .delete
        }
    }

    /// Query items for GET requests.
    var queryItems: [URLQueryItem]? {
        switch self {
        case .doseRecords(let from, let to):
            let formatter = ISO8601DateFormatter()
            return [
                URLQueryItem(name: "from", value: formatter.string(from: from)),
                URLQueryItem(name: "to", value: formatter.string(from: to)),
            ]
        default:
            return nil
        }
    }

    /// JSON body, already encoded. `nil` for requests that carry none.
    ///
    /// Encoding here rather than at the call site means a body and its
    /// endpoint can never drift apart.
    func body() throws -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        switch self {
        case .signIn(let email, let password):
            return try encoder.encode(["email": email, "password": password])
        case .signUp(let name, let email, let password):
            return try encoder.encode(["name": name, "email": email, "password": password])
        case .createMedicine(let medicine), .updateMedicine(let medicine):
            return try encoder.encode(medicine)
        case .recordDose(let record):
            return try encoder.encode(record)
        case .linkCaretaker(let shareCode):
            return try encoder.encode(["shareCode": shareCode])
        default:
            return nil
        }
    }
}
