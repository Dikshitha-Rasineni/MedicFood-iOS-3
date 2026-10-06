import Foundation
import FirebaseFirestore

/// Medicines, stored exactly where the Android app keeps them:
/// `users/{uid}/medicine_schedules/current_schedule`, as a map under
/// `medicines` keyed by medicine id.
///
/// Writes touch **one key of that map**, never the whole map. Android reads and
/// rewrites the entire document, so a read-modify-write here would silently
/// drop any medicine added on the phone between this app's read and its write.
/// `setData(merge:)` with a single nested key lets the server do the merge.
///
/// `doses(on:)` is inherited from `MedicineServicing` — doses are derived from
/// the medicine list, so this service never stores them.
@MainActor
final class FirestoreMedicineService: MedicineServicing {

    /// Medicines are read on nearly every screen. One cached copy per fetch
    /// keeps `medicine(id:)` from pulling the whole document again, and is
    /// invalidated by every write this service makes.
    private var cache: [Medicine]?

    func medicines() async throws -> [Medicine] {
        if let cache { return cache }

        let uid = try FirestoreClient.requireUID()
        let snapshot = try await FirestoreClient.scheduleDocument(uid).getDocument()
        let document = FirestoreClient.normalised(snapshot.data())

        let medicines = FirestoreSchema.medicines(from: document)
        cache = medicines
        return medicines
    }

    func medicine(id: UUID) async throws -> Medicine? {
        try await medicines().first { $0.id == id }
    }

    func save(_ medicine: Medicine) async throws {
        let uid = try FirestoreClient.requireUID()

        // A medicine created on this device has no document key yet. Its own
        // UUID becomes the key: Android treats ids as opaque strings, and it
        // keeps the local object's identity — and therefore every reminder
        // already scheduled against it — intact after the round trip.
        let key = medicine.remoteID ?? medicine.id.uuidString

        var fields = FirestoreSchema.fields(for: medicine)
        fields["updatedAt"] = FieldValue.serverTimestamp()
        if medicine.remoteID == nil {
            fields["createdAt"] = FieldValue.serverTimestamp()
        }

        try await FirestoreClient.scheduleDocument(uid).setData(
            [
                "medicines": [key: fields],
                "updatedAt": FieldValue.serverTimestamp(),
            ],
            merge: true
        )
        cache = nil
    }

    func delete(id: UUID) async throws {
        let uid = try FirestoreClient.requireUID()
        guard let medicine = try await medicine(id: id) else { throw ServiceError.notFound }
        let key = medicine.remoteID ?? medicine.id.uuidString

        // Deleting one key of the map, rather than writing the map back without
        // it — same reason as `save`.
        try await FirestoreClient.scheduleDocument(uid).updateData([
            FieldPath(["medicines", key]): FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        cache = nil
    }

    /// Drop the cached copy, so the next read hits Firestore. Called when the
    /// app returns to the foreground, where another device may have written.
    func invalidate() { cache = nil }
}
