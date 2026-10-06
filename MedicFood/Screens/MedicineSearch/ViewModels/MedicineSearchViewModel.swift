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
    private var suggestTask: Task<Void, Never>?

    /// Autocomplete lines for the search box.
    private(set) var suggestions: [DrugSuggestion] = []

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
        suggestTask?.cancel()
        let text = query

        // Suggestions are local and cheap, so they get a shorter pause than the
        // search itself and appear while the results are still pending.
        suggestTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.refreshSuggestions(for: text)
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    func refreshSuggestions(for text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { suggestions = []; return }

        let found = await service.suggestions(for: trimmed, limit: 6)
        // The user may have kept typing while that ran.
        guard trimmed == query.trimmingCharacters(in: .whitespaces) else { return }
        suggestions = DrugSuggestion.pruned(found, query: trimmed)
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
