import Foundation
import Observation

/// Drives the adherence screen: how well the user is keeping to the schedule.
@MainActor
@Observable
final class AdherenceViewModel {

    enum Period: String, CaseIterable, Identifiable {
        case week, month

        var id: String { rawValue }
        var displayName: String { self == .week ? "7 days" : "30 days" }
        var days: Int { self == .week ? 7 : 30 }
    }

    /// One day's figures, for the bar chart.
    struct DayBar: Identifiable, Hashable {
        let date: Date
        let taken: Int
        let total: Int

        var id: Date { date }
        var rate: Double { total == 0 ? 0 : Double(taken) / Double(total) }
        var hasDoses: Bool { total > 0 }
    }

    var period: Period = .week {
        didSet { Task { await load() } }
    }

    private(set) var stats = AdherenceStats()
    private(set) var bars: [DayBar] = []
    private(set) var upcoming = 0
    private(set) var isLoading = false

    private let medicines: MedicineServicing
    private let adherence: AdherenceServicing

    init(medicines: MedicineServicing, adherence: AdherenceServicing) {
        self.medicines = medicines
        self.adherence = adherence
    }

    convenience init(services: ServiceContainer) {
        self.init(medicines: services.medicines, adherence: services.adherence)
    }

    var currentStreak: Int {
        var streak = 0
        // Walk backwards from the most recent complete day.
        for bar in bars.reversed() where bar.hasDoses {
            guard bar.rate >= 1.0 else { break }
            streak += 1
        }
        return streak
    }

    var headline: String {
        switch stats.rate {
        case 0.9...:    "Excellent"
        case 0.7..<0.9: "Good"
        case 0.5..<0.7: "Needs attention"
        default:        "Let's get back on track"
        }
    }

    /// Builds the per-day figures.
    ///
    /// A past dose with no recorded outcome counts as **missed**. The service
    /// only reports what was recorded; deciding that silence in the past means
    /// a missed dose is a scheduling judgement, so it belongs here where the
    /// schedule is known.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var built: [DayBar] = []
        var totals = AdherenceStats()
        var upcomingCount = 0

        for offset in stride(from: period.days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let doses = (try? await medicines.doses(on: day)) ?? []

            var takenToday = 0
            for dose in doses {
                let outcome = await adherence.outcome(for: dose.id)
                switch outcome {
                case .taken:
                    takenToday += 1
                    totals.taken += 1
                case .skipped:
                    totals.skipped += 1
                case .missed:
                    totals.missed += 1
                case .none:
                    // Only count silence as missed once the dose is in the past.
                    if dose.scheduledAt < .now { totals.missed += 1 } else { upcomingCount += 1 }
                }
            }

            built.append(DayBar(date: day, taken: takenToday, total: doses.count))
        }

        bars = built
        stats = totals
        upcoming = upcomingCount
    }
}
