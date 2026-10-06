import Foundation
import FirebaseFirestore

/// What happened to each dose, in `users/{uid}/adherence/{id}`.
///
/// The document id is rebuilt from the dose rather than stored
/// (`FirestoreSchema.adherenceDocumentID`), so marking the same dose taken on
/// the phone and on iOS writes to one document instead of two. Without that the
/// adherence rate counts a single tablet twice.
///
/// Note there is no `snooze` here, by design — see `AdherenceServicing`.
@MainActor
final class FirestoreAdherenceService: AdherenceServicing {

    /// `outcome(for:)` is called for every row the dashboard draws, so it must
    /// not hit the network each time. Records for a day are fetched once and
    /// held here, keyed by `DoseRecord.id`.
    private var cache: [String: DoseRecord] = [:]
    private var loadedDays: Set<String> = []

    func record(_ outcome: DoseOutcome, for dose: Dose) async throws {
        let uid = try FirestoreClient.requireUID()
        let key = dose.medicine.remoteID ?? dose.medicine.id.uuidString

        let record = DoseRecord(
            id: dose.id,
            medicineID: dose.medicine.id,
            medicineName: dose.medicine.name,
            slot: dose.slot,
            scheduledAt: dose.scheduledAt,
            outcome: outcome
        )

        let documentID = FirestoreSchema.adherenceDocumentID(
            medicineRemoteID: key, scheduledAt: dose.scheduledAt
        )
        var document = FirestoreSchema.adherenceDocument(
            for: record, userID: uid, medicineRemoteID: key
        )
        document["updatedAt"] = FieldValue.serverTimestamp()

        try await FirestoreClient.adherenceCollection(uid)
            .document(documentID)
            .setData(document, merge: true)

        cache[record.id] = record
    }

    func outcome(for doseID: String) async -> DoseOutcome? {
        // The caller is drawing a row and cannot wait on a round trip, so this
        // answers from whatever `records(from:to:)` has already loaded. A dose
        // whose day has not been loaded reads as "not yet actioned", which is
        // the same thing an empty backend would say.
        cache[doseID]?.outcome
    }

    func records(from: Date, to: Date) async throws -> [DoseRecord] {
        let uid = try FirestoreClient.requireUID()
        let start = FirestoreSchema.dayFormatter.string(from: from)
        let end = FirestoreSchema.dayFormatter.string(from: to)

        // `date` is stored as `yyyy-MM-dd`, which sorts lexicographically the
        // same way it sorts chronologically — so a string range works and no
        // composite index is needed.
        let snapshot = try await FirestoreClient.adherenceCollection(uid)
            .whereField("date", isGreaterThanOrEqualTo: start)
            .whereField("date", isLessThanOrEqualTo: end)
            .getDocuments()

        let medicinesByID = Dictionary(
            uniqueKeysWithValues: (try? await medicineLookup()) ?? []
        )

        let records = snapshot.documents.compactMap { document in
            FirestoreSchema.doseRecord(
                from: FirestoreClient.normalised(document.data()),
                medicines: medicinesByID
            )
        }

        for record in records { cache[record.id] = record }
        loadedDays.insert(start)
        return records.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func stats(from: Date, to: Date) async throws -> AdherenceStats {
        let records = try await records(from: from, to: to)
        var stats = AdherenceStats()
        for record in records {
            switch record.outcome {
            case .taken:   stats.taken += 1
            case .skipped: stats.skipped += 1
            case .missed:  stats.missed += 1
            }
        }
        return stats
    }

    /// Records carry a medicine id but not which slot the dose belonged to, so
    /// the medicine list is needed to recover it. Best effort: a record for a
    /// deleted medicine still reads back, just with the slot inferred from its
    /// clock time.
    private func medicineLookup() async throws -> [(UUID, Medicine)] {
        let service = FirestoreMedicineService()
        return try await service.medicines().map { ($0.id, $0) }
    }
}
