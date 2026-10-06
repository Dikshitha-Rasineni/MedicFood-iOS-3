import Foundation
import Observation

@MainActor
@Observable
final class DrugFoodInteractionViewModel {

    var query = ""

    private(set) var results: [DrugInfo] = []
    private(set) var interactions: [FoodInteraction] = []

    private(set) var isSearching = false
    private(set) var isLoadingInteractions = false
    private(set) var errorMessage: String?

    /// Cache of food interactions keyed by drug id (rxcui). This is the
    /// smallest addition needed to let dashboard cards surface a food
    /// interaction summary without re-fetching on every re-render, and it
    /// doubles as a cache for the detail screen so re-opening a drug the
    /// dashboard already summarized is instant. No new service/API was
    /// introduced — this just reuses `service.foodInteractions(for:)`.
    private(set) var interactionsByDrugID: [String: [FoodInteraction]] = [:]

    private let service: DrugInfoServicing

    init(service: DrugInfoServicing) {
        self.service = service
    }

    convenience init(services: ServiceContainer) {
        self.init(service: services.drugInfo)
    }

    var hasSearched: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isEmpty: Bool {
        !isSearching && results.isEmpty
    }

    func loadCatalogue() async {
        isSearching = true
        errorMessage = nil

        defer {
            isSearching = false
        }

        do {
            results = try await service.search("")
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            await loadCatalogue()
            return
        }

        isSearching = true
        errorMessage = nil

        defer {
            isSearching = false
        }

        do {
            results = try await service.search(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    /// Loads (and caches) the full interaction list for the detail screen.
    func loadInteractions(for drug: DrugInfo) async {
        if let cached = interactionsByDrugID[drug.id] {
            interactions = cached
            return
        }

        isLoadingInteractions = true
        errorMessage = nil

        defer {
            isLoadingInteractions = false
        }

        do {
            let items = try await service.foodInteractions(for: drug.name)
            interactionsByDrugID[drug.id] = items
            interactions = items
        } catch {
            errorMessage = error.localizedDescription
            interactions = []
        }
    }

    /// Loads (and caches) interactions for a dashboard card summary, without
    /// touching `interactions`/`isLoadingInteractions`, which belong to the
    /// detail screen's larger loading state.
    func loadInteractionSummary(for drug: DrugInfo) async {
        guard interactionsByDrugID[drug.id] == nil else { return }

        do {
            interactionsByDrugID[drug.id] = try await service.foodInteractions(for: drug.name)
        } catch {
            interactionsByDrugID[drug.id] = []
        }
    }

    /// The single most important interaction for a compact dashboard card,
    /// using avoid > caution > minor priority.
    func topInteraction(for drug: DrugInfo) -> FoodInteraction? {
        interactionsByDrugID[drug.id]?.min { $0.severity.order < $1.severity.order }
    }
}
