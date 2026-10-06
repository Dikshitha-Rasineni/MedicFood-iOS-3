import XCTest
@testable import MedicFood

/// The catalogue that ships inside the app, tested as shipped.
///
/// Most of these run against the real `drug_food_catalogue.json`, not a
/// fixture: the failure worth catching is someone editing the data and
/// breaking it, and a fixture cannot notice that.
@MainActor
final class BundledDrugInfoServiceTests: XCTestCase {

    private var service: BundledDrugInfoService!

    override func setUp() async throws {
        service = BundledDrugInfoService()
    }

    // MARK: - The data itself

    func testShippedCatalogueLoadsAndIsNotTrivial() {
        XCTAssertGreaterThanOrEqual(service.entries.count, 100)
    }

    /// An entry that yields no rows would show "No food interactions recorded"
    /// for a drug that is in the catalogue — indistinguishable from a gap.
    func testEveryEntryProducesAtLeastOneRow() async throws {
        for entry in service.entries {
            let rows = DrugCatalogueMapping.interactions(from: entry.fields)
            XCTAssertFalse(rows.isEmpty, "\(entry.drugName) has no usable food advice")
        }
    }

    func testNoPlaceholderTextLeaksIntoRows() async throws {
        for entry in service.entries {
            for row in DrugCatalogueMapping.interactions(from: entry.fields) {
                XCTAssertNotEqual(row.food.lowercased(), "na", entry.drugName)
                XCTAssertNotEqual(row.effect.lowercased(), "na", entry.drugName)
            }
        }
    }

    func testNamesAndBrandNamesAreUnique() {
        let all = service.entries.flatMap(\.names)
        XCTAssertEqual(all.count, Set(all).count, "a brand name points at two drugs")
    }

    /// If the entry says there is something to avoid, it must also say why —
    /// otherwise the row shows the generic fallback sentence.
    func testEveryAvoidRowHasAReason() {
        for entry in service.entries where DrugCatalogueMapping.value(entry.foodToAvoid) != nil {
            XCTAssertNotNil(
                DrugCatalogueMapping.value(entry.interactingWith),
                "\(entry.drugName) says to avoid something but not why"
            )
        }
    }

    // MARK: - Searching

    func testSearchFindsByPrefixAnyCase() async throws {
        for query in ["amox", "AMOX", "Amox"] {
            let names = try await service.search(query).map(\.name)
            XCTAssertTrue(names.contains("Amoxicillin"), "'\(query)' found \(names)")
        }
    }

    /// The live prefix query could not do this.
    func testSearchFindsMidWord() async throws {
        let names = try await service.search("formin").map(\.name)
        XCTAssertTrue(names.contains("Metformin"))
    }

    func testSearchFindsByBrandName() async throws {
        let dolo = try await service.search("Dolo").map(\.name)
        XCTAssertEqual(dolo, ["Paracetamol"])
        let ecosprin = try await service.search("ecosprin").map(\.name)
        XCTAssertEqual(ecosprin, ["Aspirin"])
    }

    func testPrefixMatchesRankAboveMidWordMatches() async throws {
        let results = try await service.search("met")

        // For each result: does any of the drug's names start with the query?
        let startsWithQuery: [Bool] = results.map { result in
            service.entries.first { $0.drugName == result.name }!
                .names.contains { $0.hasPrefix("met") }
        }

        XCTAssertTrue(startsWithQuery.contains(true), "expected some prefix matches for 'met'")
        XCTAssertTrue(startsWithQuery.contains(false), "expected some mid-word matches too, or this test proves nothing")

        // Once a mid-word match appears, no prefix match may follow it.
        let firstMidWord = startsWithQuery.firstIndex(of: false)!
        XCTAssertFalse(
            startsWithQuery[firstMidWord...].contains(true),
            "a prefix match was ranked below a mid-word match"
        )
    }

    func testEmptySearchBrowsesTheWholeCatalogueAlphabetically() async throws {
        let names = try await service.search("").map(\.name)
        XCTAssertEqual(names.count, service.entries.count)
        XCTAssertEqual(names, names.sorted())
    }

    func testNoMatchReturnsEmptyRatherThanThrowing() async throws {
        let results = try await service.search("zzzzqqqq")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Looking up food advice

    func testLooksUpByNameAndByBrand() async throws {
        let byName = try await service.foodInteractions(for: "Warfarin")
        let byBrand = try await service.foodInteractions(for: "Coumadin")
        XCTAssertFalse(byName.isEmpty)
        XCTAssertEqual(byName.map(\.food), byBrand.map(\.food))
    }

    func testAvoidRowsComeBeforeTakeRows() async throws {
        let rows = try await service.foodInteractions(for: "Metformin")
        XCTAssertEqual(rows.first?.severity, .avoid)
        XCTAssertEqual(rows.first?.food, "Heavy alcohol")
    }

    /// A scanned prescription, end to end through the normaliser.
    func testScannedPrescriptionNamesResolve() async throws {
        let scans = [
            "Tab. METFORMIN HCl 850MG",
            "Cap Omeprazole 20mg",
            "AMOXICILLIN 500MG",
            "Tab. Ciprofloxacin 500 mg BD",
            "Vitamin D3 60,000 IU",
        ]
        for scan in scans {
            var found = false
            for candidate in DrugNameNormalizer.candidates(from: scan) {
                if try await !service.foodInteractions(for: candidate).isEmpty { found = true; break }
            }
            XCTAssertTrue(found, "\"\(scan)\" did not resolve to any catalogue entry")
        }
    }

    /// The reason lookup is exact: a near-miss must return nothing, not the
    /// nearest drug's advice.
    func testLookupDoesNotGuess() async throws {
        let partial = try await service.foodInteractions(for: "Vitamin")
        XCTAssertTrue(partial.isEmpty)
        let nearby = try await service.foodInteractions(for: "Metformi")
        XCTAssertTrue(nearby.isEmpty)
    }

    // MARK: - Medicines the user is likely to have

    /// The five the demo data uses, plus the common ones a first-time user
    /// would try. If one of these goes missing the demo breaks in public.
    func testCommonMedicinesArePresent() async throws {
        let common = ["Paracetamol", "Aspirin", "Metformin", "Amoxicillin", "Atorvastatin",
                      "Amlodipine", "Omeprazole", "Levothyroxine", "Warfarin", "Vitamin D3",
                      "Ciprofloxacin", "Ibuprofen", "Cetirizine", "Azithromycin", "Pantoprazole"]
        for name in common {
            let rows = try await service.foodInteractions(for: name)
            XCTAssertFalse(rows.isEmpty, "\(name) is missing")
        }
    }
}

// MARK: - Fallback

@MainActor
final class FallbackDrugInfoServiceTests: XCTestCase {

    private struct Offline: Error {}

    private final class Stub: DrugInfoServicing {
        var searchResult: Result<[DrugInfo], Error> = .success([])
        var interactionResult: Result<[FoodInteraction], Error> = .success([])
        func search(_ query: String) async throws -> [DrugInfo] { try searchResult.get() }
        func details(rxcui: String) async throws -> DrugInfo? { nil }
        func foodInteractions(for drugName: String) async throws -> [FoodInteraction] { try interactionResult.get() }
    }

    private func interaction() -> FoodInteraction {
        FoodInteraction(food: "Alcohol", effect: "Avoid", severity: .avoid)
    }

    func testPrimaryWinsWhenItHasAnAnswer() async throws {
        let primary = Stub(), fallback = Stub()
        primary.interactionResult = .success([interaction()])
        fallback.interactionResult = .success([FoodInteraction(food: "Other", effect: "x", severity: .minor)])

        let service = FallbackDrugInfoService(primary: primary, fallback: fallback)
        let rows = try await service.foodInteractions(for: "X")
        XCTAssertEqual(rows.first?.food, "Alcohol")
    }

    func testFallsBackWhenPrimaryHasNothing() async throws {
        let primary = Stub(), fallback = Stub()
        fallback.interactionResult = .success([interaction()])

        let service = FallbackDrugInfoService(primary: primary, fallback: fallback)
        let rows = try await service.foodInteractions(for: "X")
        XCTAssertEqual(rows.count, 1)
    }

    func testFallsBackWhenPrimaryFails() async throws {
        let primary = Stub(), fallback = Stub()
        primary.interactionResult = .failure(Offline())
        fallback.interactionResult = .success([interaction()])

        let service = FallbackDrugInfoService(primary: primary, fallback: fallback)
        let rows = try await service.foodInteractions(for: "X")
        XCTAssertEqual(rows.count, 1, "a catalogue we do have must answer when the server cannot")
    }

    /// The safety property: nobody was able to check, so the result must not
    /// read as "checked and clear".
    func testFailureWithNoFallbackAnswerIsNotReportedAsEmpty() async {
        let primary = Stub(), fallback = Stub()
        primary.interactionResult = .failure(Offline())

        let service = FallbackDrugInfoService(primary: primary, fallback: fallback)
        do {
            let rows = try await service.foodInteractions(for: "X")
            XCTFail("expected a thrown error, got \(rows)")
        } catch {
            XCTAssertTrue(error is Offline)
        }
    }

    func testSearchFallsBackToo() async throws {
        let primary = Stub(), fallback = Stub()
        primary.searchResult = .failure(Offline())
        fallback.searchResult = .success([DrugInfo(rxcui: "1", name: "Aspirin")])

        let service = FallbackDrugInfoService(primary: primary, fallback: fallback)
        let results = try await service.search("asp")
        XCTAssertEqual(results.map(\.name), ["Aspirin"])
    }
}
