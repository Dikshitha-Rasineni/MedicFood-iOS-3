import XCTest
@testable import MedicFood

/// The join between a prescribed medicine and the food-interaction catalogue.
///
/// This is the feature the app exists for — "what can I eat with this" — so the
/// behaviour that matters is tested directly, including the two ways it can be
/// quietly wrong: looking up a messy OCR name, and reporting a failed lookup as
/// "nothing to worry about".
@MainActor
final class MedicineFoodViewModelTests: XCTestCase {

    private func medicine(named name: String) -> Medicine {
        Medicine(name: name, dosage: "500 mg", slots: [.morning])
    }

    // MARK: - The happy path

    func testFindsInteractionsForAPlainName() async {
        let model = MedicineFoodViewModel(drugInfo: MockDrugInfoService())
        await model.load(for: medicine(named: "Amoxicillin"))

        guard case .found(let interactions, let matched) = model.state else {
            return XCTFail("expected interactions, got \(model.state)")
        }
        XCTAssertFalse(interactions.isEmpty)
        XCTAssertEqual(matched, "Amoxicillin")
    }

    /// The whole reason the normaliser exists: this is what a scan produces,
    /// and before the join it matched nothing.
    func testFindsInteractionsForAScannedName() async {
        let model = MedicineFoodViewModel(drugInfo: MockDrugInfoService())
        await model.load(for: medicine(named: "Tab. AMOXICILLIN 500MG"))

        guard case .found(_, let matched) = model.state else {
            return XCTFail("a scanned name must still match, got \(model.state)")
        }
        XCTAssertEqual(matched, "Amoxicillin")
    }

    /// Severities arrive sorted, so "avoid" is never buried under "minor".
    func testMostSevereInteractionComesFirst() async {
        let model = MedicineFoodViewModel(drugInfo: MockDrugInfoService())
        await model.load(for: medicine(named: "Warfarin"))

        guard case .found(let interactions, _) = model.state else {
            return XCTFail("expected interactions, got \(model.state)")
        }
        let orders = interactions.map(\.severity.order)
        XCTAssertEqual(orders, orders.sorted(), "interactions must be ordered most severe first")
    }

    // MARK: - The two dangerous failures

    /// A drug with no entry says so, naming what it searched for — it must not
    /// look like an error.
    func testUnknownDrugReportsNothingFound() async {
        let model = MedicineFoodViewModel(drugInfo: MockDrugInfoService())
        await model.load(for: medicine(named: "Zyxomab"))

        guard case .none(let searched) = model.state else {
            return XCTFail("expected a clean no-result, got \(model.state)")
        }
        XCTAssertEqual(searched, "Zyxomab")
    }

    /// The one that could hurt someone: if the lookup *fails*, the screen must
    /// not imply the medicine is safe with food.
    func testLookupFailureIsNeverReportedAsNoInteractions() async {
        let model = MedicineFoodViewModel(drugInfo: FailingDrugInfoService())
        await model.load(for: medicine(named: "Amoxicillin"))

        guard case .failed = model.state else {
            return XCTFail("a failed lookup must surface as a failure, got \(model.state)")
        }
    }

    func testEmptyNameDoesNotSearch() async {
        let service = CountingDrugInfoService()
        let model = MedicineFoodViewModel(drugInfo: service)
        await model.load(for: medicine(named: " "))

        XCTAssertEqual(service.calls, 0, "an unusable name must not hit the service")
        guard case .none = model.state else {
            return XCTFail("expected a clean no-result, got \(model.state)")
        }
    }
}

// MARK: - Doubles

@MainActor
private final class FailingDrugInfoService: DrugInfoServicing {
    struct Offline: LocalizedError { var errorDescription: String? { "Could not reach the server." } }

    func search(_ query: String) async throws -> [DrugInfo] { throw Offline() }
    func details(rxcui: String) async throws -> DrugInfo? { throw Offline() }
    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] { throw Offline() }
}

@MainActor
private final class CountingDrugInfoService: DrugInfoServicing {
    private(set) var calls = 0

    func search(_ query: String) async throws -> [DrugInfo] { [] }
    func details(rxcui: String) async throws -> DrugInfo? { nil }
    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] {
        calls += 1
        return []
    }
}
