import Foundation
import FirebaseFirestore

/// Caretaker links, kept the way Android keeps them: an array of cached
/// patient profiles on the caretaker's own `users/{uid}` document, each
/// carrying two counters (`medicinesCount`, `medicinesTaken`) that the
/// patient's app refreshes.
///
/// The cached copy is why a patient's name can be stale or missing — that is
/// the existing behaviour on Android, not a bug introduced here.
@MainActor
final class FirestoreCaretakerService: CaretakerServicing {

    func patients() async throws -> [LinkedPatient] {
        let uid = try FirestoreClient.requireUID()
        let snapshot = try await FirestoreClient.userDocument(uid).getDocument()
        return FirestoreSchema.linkedPatients(from: FirestoreClient.normalised(snapshot.data()))
    }

    func link(shareCode: String) async throws -> LinkedPatient {
        let uid = try FirestoreClient.requireUID()
        let code = shareCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let matches = try await FirestoreClient.db
            .collection(FirestoreSchema.Path.users)
            .whereField("shareCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()

        guard let document = matches.documents.first else { throw ServiceError.shareCodeUnknown }
        guard document.documentID != uid else { throw ServiceError.alreadyLinked }

        let fields = FirestoreClient.normalised(document.data())
        let existing = try await patients()
        guard !existing.contains(where: { $0.id == document.documentID }) else {
            throw ServiceError.alreadyLinked
        }

        // Stored as Android stores it, including the fields this app does not
        // read, so the patient still appears correctly on the phone.
        let entry: [String: Any] = [
            "uid": document.documentID,
            "name": fields["name"] as? String
                ?? (fields["email"] as? String)?.components(separatedBy: "@").first
                ?? "Dependent",
            "email": fields["email"] as? String ?? "",
            "shareCode": code,
            "medicinesCount": 0,
            "medicinesTaken": 0,
            "lastSync": FieldValue.serverTimestamp(),
        ]

        try await FirestoreClient.userDocument(uid).setData(
            ["patients": FieldValue.arrayUnion([entry])],
            merge: true
        )

        return LinkedPatient(
            id: document.documentID,
            name: entry["name"] as? String ?? "Dependent",
            adherenceRate: 0,
            dosesToday: 0,
            takenToday: 0,
            lastActive: nil
        )
    }

    func unlink(patientID: String) async throws {
        let uid = try FirestoreClient.requireUID()
        let reference = FirestoreClient.userDocument(uid)
        let snapshot = try await reference.getDocument()

        guard let entries = snapshot.data()?["patients"] as? [[String: Any]] else { return }

        // `arrayRemove` matches on the whole element, and these entries carry a
        // server timestamp this app cannot reproduce exactly — so the array is
        // filtered and written back instead.
        let remaining = entries.filter { ($0["uid"] as? String) != patientID }
        guard remaining.count != entries.count else { throw ServiceError.notFound }

        try await reference.setData(["patients": remaining], merge: true)
    }
}
