import XCTest
@testable import MedicFood

/// Autocomplete for the drug search boxes.
@MainActor
final class AutocompleteTests: XCTestCase {

    private var service: BundledDrugInfoService!

    override func setUp() async throws {
        service = BundledDrugInfoService()
    }

    // MARK: - What it suggests

    func testSuggestsDrugsByPrefix() async {
        let suggestions = await service.suggestions(for: "amo", limit: 6)
        XCTAssertEqual(suggestions.first?.title, "Amoxicillin")
        XCTAssertNil(suggestions.first?.subtitle, "a drug's own name has no 'brand of' line")
    }

    /// The point of aliases: the user types the name they know.
    func testBrandNameSuggestsItsDrug() async throws {
        let suggestions = await service.suggestions(for: "dol", limit: 6)
        let dolo = try XCTUnwrap(suggestions.first { $0.title == "Dolo" })
        XCTAssertEqual(dolo.subtitle, "Paracetamol")
        XCTAssertEqual(dolo.completion, "Paracetamol", "choosing a brand must search for the generic")
    }

    func testMatchesMidWordAndIgnoresCase() async {
        let mid = await service.suggestions(for: "FORMIN", limit: 6)
        XCTAssertTrue(mid.contains { $0.completion == "Metformin" })
    }

    func testRespectsTheLimit() async {
        let suggestions = await service.suggestions(for: "a", limit: 4)
        XCTAssertEqual(suggestions.count, 4)
    }

    func testOneLinePerDrug() async {
        let suggestions = await service.suggestions(for: "amox", limit: 20)
        let drugs = suggestions.map(\.completion)
        XCTAssertEqual(drugs.count, Set(drugs).count, "a drug appeared twice: \(suggestions.map(\.title))")
    }

    func testPrefixMatchesRankFirstAndGenericBeatsBrand() async {
        let suggestions = await service.suggestions(for: "para", limit: 6)
        XCTAssertEqual(suggestions.first?.title, "Paracetamol")
    }

    func testNothingForEmptyOrUnknown() async {
        let empty = await service.suggestions(for: "", limit: 6)
        let spaces = await service.suggestions(for: "   ", limit: 6)
        let unknown = await service.suggestions(for: "zzzzqq", limit: 6)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(spaces.isEmpty)
        XCTAssertTrue(unknown.isEmpty)
    }

    // MARK: - Choosing one must not summon it back

    func testPruneRemovesAnExactMatchOfTheDrugItself() {
        let list = [DrugSuggestion(title: "Aspirin", subtitle: nil, completion: "Aspirin")]
        XCTAssertTrue(DrugSuggestion.pruned(list, query: "aspirin").isEmpty)
    }

    /// A brand typed in full still maps somewhere useful, so it stays.
    func testPruneKeepsAFullyTypedBrandName() {
        let list = [DrugSuggestion(title: "Dolo", subtitle: "Paracetamol", completion: "Paracetamol")]
        XCTAssertEqual(DrugSuggestion.pruned(list, query: "Dolo").count, 1)
    }

    // MARK: - View models

    func testDrugFoodScreenNarrowsResultsAndSuggestsAsYouType() async throws {
        let model = DrugFoodInteractionViewModel(service: service)
        model.query = "met"
        await model.refresh(for: "met")

        XCTAssertFalse(model.suggestions.isEmpty)
        XCTAssertTrue(model.results.contains { $0.name == "Metformin" })
        XCTAssertFalse(model.results.contains { $0.name == "Acarbose" }, "results must narrow, not stay on the full list")
    }

    func testSelectingASuggestionSearchesForTheDrugAndClosesTheList() async throws {
        let model = DrugFoodInteractionViewModel(service: service)
        model.query = "dol"
        await model.refresh(for: "dol")
        let dolo = try XCTUnwrap(model.suggestions.first { $0.title == "Dolo" })

        await model.select(dolo)

        XCTAssertEqual(model.query, "Paracetamol")
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertEqual(model.results.map(\.name), ["Paracetamol"])
    }

    /// Picking a suggestion sets the query, which triggers a refresh; that
    /// refresh must not bring the same line straight back.
    func testRefreshingAfterASelectionOffersNothingMore() async throws {
        let model = DrugFoodInteractionViewModel(service: service)
        model.query = "Aspirin"
        await model.refresh(for: "Aspirin")
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testClearingTheBoxRestoresTheFullList() async {
        let model = DrugFoodInteractionViewModel(service: service)
        model.query = "met"
        await model.refresh(for: "met")
        let narrowed = model.results.count

        model.query = ""
        await model.refresh(for: "")

        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertGreaterThan(model.results.count, narrowed)
    }

    func testMedicineSearchSuggestsAsYouType() async {
        let model = MedicineSearchViewModel(service: service)
        model.query = "ibu"
        await model.refreshSuggestions(for: "ibu")
        XCTAssertEqual(model.suggestions.first?.title, "Ibuprofen")
    }

    // MARK: - Fallback

    private final class Stub: DrugInfoServicing {
        var suggested: [DrugSuggestion] = []
        private(set) var asked = 0
        func search(_ query: String) async throws -> [DrugInfo] { [] }
        func details(rxcui: String) async throws -> DrugInfo? { nil }
        func foodInteractions(for drugName: String) async throws -> [FoodInteraction] { [] }
        func suggestions(for query: String, limit: Int) async -> [DrugSuggestion] { asked += 1; return suggested }
    }

    /// Suggestions are asked for on every pause in typing, so the network
    /// source must not be touched when the local one can answer.
    func testSuggestionsUseTheLocalCatalogueBeforeTheNetwork() async {
        let primary = Stub()
        primary.suggested = [DrugSuggestion(title: "Remote", subtitle: nil, completion: "Remote")]
        let combined = FallbackDrugInfoService(primary: primary, fallback: service)

        let suggestions = await combined.suggestions(for: "amo", limit: 6)

        XCTAssertEqual(suggestions.first?.title, "Amoxicillin")
        XCTAssertEqual(primary.asked, 0, "the network source was hit although the local one had an answer")
    }

    func testSuggestionsFallThroughToTheNetworkWhenLocalHasNone() async {
        let primary = Stub()
        primary.suggested = [DrugSuggestion(title: "Zyxomab", subtitle: nil, completion: "Zyxomab")]
        let combined = FallbackDrugInfoService(primary: primary, fallback: service)

        let suggestions = await combined.suggestions(for: "zyx", limit: 6)
        XCTAssertEqual(suggestions.map(\.title), ["Zyxomab"])
    }
}
