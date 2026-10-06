import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Shared plumbing for the Firestore-backed services.
///
/// Keeps three things in one place so each service stays about its own data:
/// who is signed in, how to reach that user's documents, and the conversion of
/// Firestore's own types into the plain values `FirestoreSchema` expects.
@MainActor
enum FirestoreClient {

    static var db: Firestore { Firestore.firestore() }

    /// The signed-in user's id, or `nil` when signed out.
    static var uid: String? { Auth.auth().currentUser?.uid }

    /// Every per-user read and write goes through here, so a signed-out call
    /// fails with a clear error instead of writing to a document path
    /// containing the string "nil".
    static func requireUID() throws -> String {
        guard let uid else { throw ServiceError.notSignedIn }
        return uid
    }

    static func userDocument(_ uid: String) -> DocumentReference {
        db.collection(FirestoreSchema.Path.users).document(uid)
    }

    /// `users/{uid}/medicine_schedules/current_schedule` — the single document
    /// holding every medicine as a nested map. See `FirestoreSchema`.
    static func scheduleDocument(_ uid: String) -> DocumentReference {
        userDocument(uid)
            .collection(FirestoreSchema.Path.medicineSchedules)
            .document(FirestoreSchema.Path.currentSchedule)
    }

    static func adherenceCollection(_ uid: String) -> CollectionReference {
        userDocument(uid).collection(FirestoreSchema.Path.adherence)
    }

    /// The top-level drug/food interaction catalogue, shared by all users and
    /// written by neither app at runtime.
    static var drugCatalogue: CollectionReference {
        db.collection("medicines")
    }

    // MARK: - Normalising what comes back

    /// Firestore hands back `Timestamp`, `NSNull` and nested dictionaries of
    /// the same. `FirestoreSchema` is deliberately SDK-free, so values are
    /// flattened to `Date`, absent, and plain dictionaries here — at the one
    /// boundary where the SDK is already in scope.
    static func normalise(_ value: Any) -> Any? {
        switch value {
        case is NSNull:
            return nil
        case let timestamp as Timestamp:
            return timestamp.dateValue()
        case let dictionary as [String: Any]:
            return dictionary.compactMapValues(normalise)
        case let array as [Any]:
            return array.compactMap(normalise)
        default:
            return value
        }
    }

    static func normalised(_ document: [String: Any]?) -> [String: Any] {
        guard let document else { return [:] }
        return document.compactMapValues(normalise)
    }
}

/// Failures the service layer raises on its own, before any SDK error.
enum ServiceError: LocalizedError {
    case notSignedIn
    case notFound
    case alreadyLinked
    case shareCodeUnknown

    var errorDescription: String? {
        switch self {
        case .notSignedIn:      "You are signed out. Sign in and try again."
        case .notFound:         "That record no longer exists."
        case .alreadyLinked:    "You are already linked to this person."
        case .shareCodeUnknown: "No one was found with that share code."
        }
    }
}
