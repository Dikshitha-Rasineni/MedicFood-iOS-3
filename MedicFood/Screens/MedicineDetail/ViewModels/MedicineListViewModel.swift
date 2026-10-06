import Foundation
import Observation

/// Drives the medicine list and the detail screen.
@MainActor
@Observable
final class MedicineListViewModel {

    private(set) var medicines: [Medicine] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var searchText = ""

    private let service: MedicineServicing
    private let notifications: NotificationScheduling?

    init(service: MedicineServicing, notifications: NotificationScheduling? = nil) {
        self.service = service
        self.notifications = notifications
    }

    convenience init(services: ServiceContainer) {
        self.init(service: services.medicines, notifications: services.notifications)
    }

    var filtered: [Medicine] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return medicines }
        return medicines.filter { $0.name.lowercased().contains(query) }
    }

    var active: [Medicine] { filtered.filter { $0.isActive } }
    var inactive: [Medicine] { filtered.filter { !$0.isActive } }

    var isEmpty: Bool { !isLoading && medicines.isEmpty }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            medicines = try await service.medicines()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ medicine: Medicine) async {
        do {
            try await service.delete(id: medicine.id)
            medicines.removeAll { $0.id == medicine.id }
            await refreshReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stop reminders without losing the record of what was prescribed.
    func setActive(_ isActive: Bool, for medicine: Medicine) async {
        var updated = medicine
        updated.isActive = isActive
        do {
            try await service.save(updated)
            if let index = medicines.firstIndex(where: { $0.id == medicine.id }) {
                medicines[index] = updated
            }
            await refreshReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turn reminders on or off without touching the medicine itself.
    func setReminders(_ isOn: Bool, for medicine: Medicine) async {
        var updated = medicine
        updated.remindersEnabled = isOn
        do {
            try await service.save(updated)
            if let index = medicines.firstIndex(where: { $0.id == medicine.id }) {
                medicines[index] = updated
            }
            await refreshReminders()
        } catch {
            errorMessage = "Unable to update reminders."
        }
    }

    func testReminder(for medicine: Medicine) async {
        await notifications?.scheduleTest(for: medicine, afterSeconds: 5)
    }

    private func refreshReminders() async {
        guard let notifications else { return }
        await ReminderScheduler.refresh(medicines: service, notifications: notifications)
    }
}
