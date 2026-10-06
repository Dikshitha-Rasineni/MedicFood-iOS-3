import Foundation
import Observation

/// Drives the dashboard: today's doses and what has happened to them.
///
/// Note the imports — `Foundation` and `Observation`, no SwiftUI. That is the
/// MVVM rule this project keeps, and it is mechanically checkable: if a view
/// type appears in a ViewModel, the import gives it away in review.
///
/// It is the same rule the Flutter codebase stated ("a ViewModel never sees a
/// `BuildContext`") but could only follow in 6 of its 14 screens.
@MainActor
@Observable
final class DashboardViewModel {

    /// A dose plus whatever outcome has been recorded for it.
    struct DoseItem: Identifiable, Hashable {
        let dose: Dose
        var outcome: DoseOutcome?
        /// When the outcome was recorded — drives the "Taken 8:04 AM" badge.
        var recordedAt: Date?

        var id: String { dose.id }
        var isActioned: Bool { outcome != nil }

        /// Actions only appear once a dose is actually due. Offering "Taken"
        /// on a dose scheduled for tonight invites recording it early.
        var isDue: Bool { dose.scheduledAt <= .now }
    }

    private(set) var items: [DoseItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private let medicines: MedicineServicing
    private let adherence: AdherenceServicing
    private let notifications: NotificationScheduling

    init(
        medicines: MedicineServicing,
        adherence: AdherenceServicing,
        notifications: NotificationScheduling
    ) {
        self.medicines = medicines
        self.adherence = adherence
        self.notifications = notifications
    }

    convenience init(services: ServiceContainer) {
        self.init(
            medicines: services.medicines,
            adherence: services.adherence,
            notifications: services.notifications
        )
    }

    // MARK: - Derived state the view reads

    var takenCount: Int { items.filter { $0.outcome == .taken }.count }
    var totalCount: Int { items.count }

    /// Progress through the day, 0...1.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(takenCount) / Double(totalCount)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Doses grouped by slot, in clock order — this is how the list renders.
    var groupedBySlot: [(slot: DoseSlot, items: [DoseItem])] {
        Dictionary(grouping: items, by: { $0.dose.slot })
            .map { (slot: $0.key, items: $0.value.sorted { $0.dose.medicine.name < $1.dose.medicine.name }) }
            .sorted { $0.slot < $1.slot }
    }

    var isEmpty: Bool { !isLoading && items.isEmpty }

    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12:  "Good morning"
        case 12..<17: "Good afternoon"
        default:      "Good evening"
        }
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let doses = try await medicines.doses(on: selectedDate)

            // One ranged fetch rather than a lookup per dose — and it carries
            // the timestamp, which `outcome(for:)` alone does not.
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            let records = (try? await adherence.records(from: selectedDate, to: dayEnd)) ?? []
            let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

            var built: [DoseItem] = []
            for dose in doses {
                let record = byID[dose.id]
                let outcome: DoseOutcome?
                if let record {
                    outcome = record.outcome
                } else {
                    outcome = await adherence.outcome(for: dose.id)
                }
                built.append(DoseItem(dose: dose, outcome: outcome, recordedAt: record?.recordedAt))
            }
            items = built
            await refreshReminders()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func changeDate(to date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        await load()
    }

    func goToPreviousDay() async {
        guard let day = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        await changeDate(to: day)
    }

    func goToNextDay() async {
        guard let day = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        await changeDate(to: day)
    }

    func record(_ outcome: DoseOutcome, for item: DoseItem) async {
        do {
            try await adherence.record(outcome, for: item.dose)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].outcome = outcome
                items[index].recordedAt = .now
            }
            // An actioned dose no longer needs a reminder.
            await notifications.cancel(doseID: item.dose.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Undo — lets someone fix a mis-tap, which the Flutter version had no way
    /// to do.
    func clearOutcome(for item: DoseItem) async {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].outcome = nil
            items[index].recordedAt = nil
        }
    }

    func snooze(_ item: DoseItem, byMinutes minutes: Int = NotificationService.snoozeMinutes) async {
        await notifications.snooze(item.dose, byMinutes: minutes)
    }

    /// Re-register reminders for the days ahead.
    ///
    /// Schedules a fortnight rather than the whole course: the scheduler caps
    /// what it registers with iOS anyway, and a bounded look-ahead keeps this
    /// cheap enough to run on every dashboard load.
    private func refreshReminders() async {
        var upcoming: [Dose] = []
        for offset in 0..<14 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) else { continue }
            if let doses = try? await medicines.doses(on: day) {
                upcoming.append(contentsOf: doses.filter { $0.medicine.isReminderOn })
            }
        }
        await notifications.schedule(upcoming)
    }
}
