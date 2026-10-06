import XCTest
@testable import MedicFood

/// The matching layer between a scanned prescription and the drug catalogue.
///
/// These are the shapes OCR actually returns from a printed prescription. If
/// this breaks, the food-interaction section silently shows nothing and looks
/// like missing data rather than a lookup failure — so it is tested harder than
/// its size suggests.
final class DrugNameNormalizerTests: XCTestCase {

    private func first(_ raw: String) -> String {
        DrugNameNormalizer.primary(from: raw)
    }

    // MARK: - Dose stripping

    func testStripsDosageAndUnits() {
        XCTAssertEqual(first("AMOXICILLIN 500MG"), "Amoxicillin")
        XCTAssertEqual(first("Paracetamol 500 mg"), "Paracetamol")
        XCTAssertEqual(first("Metformin 850mg"), "Metformin")
        XCTAssertEqual(first("Aspirin 75 mg"), "Aspirin")
    }

    func testStripsDoseFormPrefix() {
        XCTAssertEqual(first("Tab. Amoxicillin 500mg"), "Amoxicillin")
        XCTAssertEqual(first("Cap Omeprazole 20mg"), "Omeprazole")
        XCTAssertEqual(first("Syp. Ibuprofen 100mg/5ml"), "Ibuprofen")
        XCTAssertEqual(first("INJ Ceftriaxone 1g"), "Ceftriaxone")
    }

    func testStripsSaltAndReleaseSuffixes() {
        XCTAssertEqual(first("Metformin HCl 850mg"), "Metformin")
        XCTAssertEqual(first("Metformin SR 500"), "Metformin")
        XCTAssertEqual(first("Amlodipine Besylate 5mg"), "Amlodipine")
    }

    // MARK: - Names that must survive

    /// The failure that makes over-trimming dangerous: "Vitamin D3" is the
    /// whole name, and cutting to one token gives the useless "Vitamin".
    func testKeepsTwoWordNames() {
        XCTAssertEqual(first("Vitamin D3 60,000 IU"), "Vitamin D3")
        XCTAssertEqual(first("VITAMIN B12 1500mcg"), "Vitamin B12")
    }

    func testKeepsHyphenatedNames() {
        // The hyphen is inside the word, so the name is not cut at it.
        XCTAssertEqual(first("Co-amoxiclav 625mg"), "Co-amoxiclav")
    }

    func testIgnoresParentheticalsAndFrequency() {
        XCTAssertEqual(first("Amoxicillin (generic) 500mg"), "Amoxicillin")
        XCTAssertEqual(first("Paracetamol 500mg TDS"), "Paracetamol")
    }

    // MARK: - Candidate order

    /// Several terms are returned so the caller can fall back, and the most
    /// specific comes first.
    func testCandidatesAreOrderedMostSpecificFirst() {
        let candidates = DrugNameNormalizer.candidates(from: "Vitamin D3 60,000 IU")
        XCTAssertEqual(candidates.first, "Vitamin D3")
        XCTAssertTrue(candidates.contains("Vitamin"), "a one-word fallback must exist")
        XCTAssertLessThan(
            candidates.firstIndex(of: "Vitamin D3") ?? .max,
            candidates.firstIndex(of: "Vitamin") ?? .max
        )
    }

    /// The catalogue query is case-sensitive, so casing is not cosmetic here.
    func testCasingMatchesTheCatalogue() {
        XCTAssertEqual(first("amoxicillin"), "Amoxicillin")
        XCTAssertEqual(first("AMOXICILLIN"), "Amoxicillin")
        XCTAssertEqual(first("aMoXiCiLLiN"), "Amoxicillin")
    }

    // MARK: - Degenerate input

    /// A name this does not understand must still be searched for rather than
    /// dropped — a bad search returns nothing, a dropped one never runs.
    func testAlwaysReturnsSomethingToSearchFor() {
        XCTAssertFalse(DrugNameNormalizer.candidates(from: "Zyxomab").isEmpty)
        XCTAssertFalse(DrugNameNormalizer.candidates(from: "Unknown 123").isEmpty)
    }

    func testEmptyInputYieldsNoCandidates() {
        XCTAssertTrue(DrugNameNormalizer.candidates(from: "").isEmpty)
        XCTAssertTrue(DrugNameNormalizer.candidates(from: "   ").isEmpty)
        // Too short to be a drug name, and would match half the catalogue.
        XCTAssertTrue(DrugNameNormalizer.candidates(from: "ab").isEmpty)
    }
}
