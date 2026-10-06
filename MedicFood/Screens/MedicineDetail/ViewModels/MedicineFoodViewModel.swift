import Foundation
import Observation

/// Finds what to eat and what to avoid for one prescribed medicine.
///
/// This is the join that was missing. Scanning a prescription produced a
/// medicine, and the catalogue of food interactions sat on a separate screen
/// the user had to go and search by hand — so the app held the answer and never
/// offered it.
///
/// The lookup goes through `DrugNameNormalizer` because the two ends do not
/// agree on spelling: a prescription says `"Tab. AMOXICILLIN 500MG"`, the
/// catalogue says `"Amoxicillin"`, and the live query is a case-sensitive
/// prefix match. Candidates are tried in order and the first hit wins.
@MainActor
@Observable
final class MedicineFoodViewModel {

    enum State: Equatable {
        case idle
        case loading
        /// Looked up successfully and the catalogue has nothing — different
        /// from a failure, and says so.
        case none(searched: String)
        case found([FoodInteraction], matched: String)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let drugInfo: DrugInfoServicing

    init(drugInfo: DrugInfoServicing) {
        self.drugInfo = drugInfo
    }

    convenience init(services: ServiceContainer) {
        self.init(drugInfo: services.drugInfo)
    }

    /// Look up `medicine`, trying each normalised candidate until one hits.
    func load(for medicine: Medicine) async {
        let candidates = DrugNameNormalizer.candidates(from: medicine.name)
        guard let primary = candidates.first else {
            state = .none(searched: medicine.name)
            return
        }

        state = .loading

        do {
            for candidate in candidates {
                let interactions = try await drugInfo.foodInteractions(for: candidate)
                if !interactions.isEmpty {
                    state = .found(
                        interactions.sorted { $0.severity.order < $1.severity.order },
                        matched: candidate
                    )
                    return
                }
            }
            // Every candidate came back empty: the lookup worked, the
            // catalogue simply has no entry.
            state = .none(searched: primary)
        } catch {
            // A failed lookup must not read as "no interactions" — that would
            // tell someone a drug is safe with food when nobody checked.
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
