import Foundation
import Observation

/// Drives Home A — the launcher.
///
/// It owns only what the launcher shows: how many reminders are set for today
/// and which dose is next. The two action cards navigate to screens that
/// already exist, so there is no new behaviour behind them.
///
/// No SwiftUI import: the view decides where a tap goes, this decides what the
/// screen says.
@MainActor
@Observable
final class HomeLauncherViewModel {

    /// The next dose still owed today.
    struct UpNext: Equatable {
        let medicineName: String
        let scheduledAt: Date
    }

    private(set) var todaysDoseCount = 0
    private(set) var upNext: UpNext?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let medicines: MedicineServicing
    private let adherence: AdherenceServicing

    init(medicines: MedicineServicing, adherence: AdherenceServicing) {
        self.medicines = medicines
        self.adherence = adherence
    }

    convenience init(services: ServiceContainer) {
        self.init(medicines: services.medicines, adherence: services.adherence)
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12:  "Good morning"
        case 12..<17: "Good afternoon"
        default:      "Good evening"
        }
    }

    /// "Hello, Vansh" when there is a name to use, the time-of-day greeting
    /// otherwise — never "Hello, " with a gap where a name should be.
    func greeting(for name: String?) -> String {
        guard let name, !name.isEmpty else { return greeting }
        return "Hello, \(name.split(separator: " ").first.map(String.init) ?? name)"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let today = Calendar.current.startOfDay(for: .now)
            let doses = try await medicines.doses(on: today)
            todaysDoseCount = doses.count

            // The next dose that is still in the future and not already actioned.
            var candidates: [Dose] = []
            for dose in doses where dose.scheduledAt > .now {
                if await adherence.outcome(for: dose.id) == nil {
                    candidates.append(dose)
                }
            }

            upNext = candidates
                .min { $0.scheduledAt < $1.scheduledAt }
                .map { UpNext(medicineName: $0.medicine.name, scheduledAt: $0.scheduledAt) }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
