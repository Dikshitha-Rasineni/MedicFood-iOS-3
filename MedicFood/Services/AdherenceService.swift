import Foundation

/// Recording what happened to each dose, and reporting on it.
///
/// Note what this protocol *cannot* express: there is no `snooze` method.
/// Snoozing reschedules a reminder and belongs to `NotificationScheduling`.
/// Keeping the two apart in the type system is what stops the bug the Flutter
/// code kept re-introducing, where a snooze was written into adherence and
/// quietly corrupted the statistics.
@MainActor
protocol AdherenceServicing: AnyObject {
    func record(_ outcome: DoseOutcome, for dose: Dose) async throws
    func outcome(for doseID: String) async -> DoseOutcome?
    func records(from: Date, to: Date) async throws -> [DoseRecord]
    func stats(from: Date, to: Date) async throws -> AdherenceStats
}

@MainActor
final class MockAdherenceService: AdherenceServicing {

    private var records: [String: DoseRecord] = [:]
    private let defaults: UserDefaults
    private static let key = "medicfood.mock.adherence"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: DoseRecord].self, from: data) {
            self.records = saved
        }
    }

    func record(_ outcome: DoseOutcome, for dose: Dose) async throws {
        records[dose.id] = DoseRecord(
            id: dose.id,
            medicineID: dose.medicine.id,
            medicineName: dose.medicine.name,
            slot: dose.slot,
            scheduledAt: dose.scheduledAt,
            outcome: outcome
        )
        persist()
    }

    func outcome(for doseID: String) async -> DoseOutcome? {
        records[doseID]?.outcome
    }

    func records(from: Date, to: Date) async throws -> [DoseRecord] {
        records.values
            .filter { $0.scheduledAt >= from && $0.scheduledAt <= to }
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    /// Counts outcomes over the period.
    ///
    /// Doses in the past with no record are counted as `missed` by the caller
    /// (`AdherenceViewModel`), which knows the schedule. This method only
    /// reports what was actually recorded — it does not guess.
    func stats(from: Date, to: Date) async throws -> AdherenceStats {
        let period = try await records(from: from, to: to)
        var stats = AdherenceStats()
        for record in period {
            switch record.outcome {
            case .taken:   stats.taken += 1
            case .skipped: stats.skipped += 1
            case .missed:  stats.missed += 1
            }
        }
        return stats
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
