import Foundation
import Observation

/// Drives drug lookup and the food-interaction list.
@MainActor
@Observable
final class MedicineSearchViewModel {

    var query = ""

    private(set) var results: [DrugInfo] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    /// Interactions for the drug currently being viewed.
    private(set) var interactions: [FoodInteraction] = []
    private(set) var isLoadingInteractions = false

    private let service: DrugInfoServicing
    /// Cancels the previous search when the user keeps typing.
    private var searchTask: Task<Void, Never>?

    init(service: DrugInfoServicing) {
        self.service = service
    }

    convenience init(services: ServiceContainer) {
        self.init(service: services.drugInfo)
    }

    var hasSearched: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var isEmpty: Bool { hasSearched && !isSearching && results.isEmpty }

    /// Debounced search.
    ///
    /// Without the delay every keystroke fires a request, which on a real
    /// network means the results flicker between stale responses arriving out
    /// of order.
    func searchDebounced() {
        searchTask?.cancel()
        let text = query

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await service.search(trimmed)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            results = []
        }
    }

    func loadInteractions(for drug: DrugInfo) async {
        isLoadingInteractions = true
        defer { isLoadingInteractions = false }
        interactions = (try? await service.foodInteractions(for: drug.name)) ?? []
    }
}
