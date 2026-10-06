import Foundation

/// Storing and reading medicines, and deriving the doses due on a day.
@MainActor
protocol MedicineServicing: AnyObject {
    func medicines() async throws -> [Medicine]
    func medicine(id: UUID) async throws -> Medicine?
    func save(_ medicine: Medicine) async throws
    func delete(id: UUID) async throws

    /// Every dose due on `date`, ordered by time.
    func doses(on date: Date) async throws -> [Dose]
}

extension MedicineServicing {
    /// Default implementation: doses are derived from the medicine list, not
    /// stored separately. Any backend gets this for free.
    func doses(on date: Date) async throws -> [Dose] {
        let all = try await medicines()
        return all
            .filter { $0.isScheduled(on: date) }
            .flatMap { medicine in
                medicine.slots.map { Dose(medicine: medicine, slot: $0, day: date) }
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }
}

/// In-memory medicine store, seeded with a realistic prescription.
///
/// Persists to `UserDefaults` so medicines survive an app relaunch during
/// development — without that, testing the reminder flow means re-entering
/// everything each launch.
@MainActor
final class MockMedicineService: MedicineServicing {

    private var storage: [Medicine]
    private let defaults: UserDefaults
    private static let key = "medicfood.mock.medicines"

    init(defaults: UserDefaults = .standard, seeded: Bool = true) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Medicine].self, from: data) {
            self.storage = saved
        } else {
            self.storage = seeded ? Self.seed() : []
        }
    }

    func medicines() async throws -> [Medicine] {
        storage.sorted { $0.name < $1.name }
    }

    func medicine(id: UUID) async throws -> Medicine? {
        storage.first { $0.id == id }
    }

    func save(_ medicine: Medicine) async throws {
        if let index = storage.firstIndex(where: { $0.id == medicine.id }) {
            storage[index] = medicine
        } else {
            storage.append(medicine)
        }
        persist()
    }

    func delete(id: UUID) async throws {
        storage.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(storage) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// A plausible prescription: one twice-daily antibiotic on a fixed course,
    /// one ongoing daily tablet, one three-times-daily painkiller. Enough
    /// variety that the dashboard, the adherence chart and the scheduler all
    /// have something real to show.
    private static func seed() -> [Medicine] {
        let today = Calendar.current.startOfDay(for: .now)
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today

        return [
            Medicine(
                name: "Amoxicillin",
                dosage: "500 mg",
                form: .capsule,
                slots: [.morning, .night],
                foodInstruction: .afterFood,
                instructions: "Finish the full course even if you feel better.",
                startDate: threeDaysAgo,
                durationDays: 7,
                isFromPrescription: true
            ),
            Medicine(
                name: "Metformin",
                dosage: "850 mg",
                form: .tablet,
                slots: [.morning, .afternoon, .night],
                foodInstruction: .withFood,
                instructions: "Take with a meal to reduce stomach upset.",
                startDate: threeDaysAgo,
                durationDays: nil          // ongoing
            ),
            Medicine(
                name: "Vitamin D3",
                dosage: "60,000 IU",
                form: .tablet,
                slots: [.morning],
                foodInstruction: .afterFood,
                startDate: threeDaysAgo,
                durationDays: 30
            ),
        ]
    }
}
