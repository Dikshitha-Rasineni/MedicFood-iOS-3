import Foundation

/// Looking up drug reference data and food interactions.
@MainActor
protocol DrugInfoServicing: AnyObject {
    func search(_ query: String) async throws -> [DrugInfo]
    func details(rxcui: String) async throws -> DrugInfo?
    func foodInteractions(for drugName: String) async throws -> [FoodInteraction]

    /// Autocomplete lines for a partly typed name. Best effort: it never
    /// throws, because failing to suggest is not worth an error on screen.
    func suggestions(for query: String, limit: Int) async -> [DrugSuggestion]
}

extension DrugInfoServicing {
    /// Default: derive suggestions from a normal search. Services that can do
    /// better cheaply — the bundled catalogue — override this.
    func suggestions(for query: String, limit: Int) async -> [DrugSuggestion] {
        guard let results = try? await search(query) else { return [] }
        return results.prefix(limit).map {
            DrugSuggestion(title: $0.name, subtitle: nil, completion: $0.name)
        }
    }
}

/// Sample drug data, so search works offline and in tests.
///
/// The real implementation calls RxNorm (`rxnav.nlm.nih.gov`) for name → RxCUI
/// resolution and openFDA (`api.fda.gov`) for label text. Both are free and
/// need no API key, so `LiveDrugInfoService` is the easiest service to switch
/// on first — see `NETWORKING_ARCHITECTURE.md`.
@MainActor
final class MockDrugInfoService: DrugInfoServicing {

    func search(_ query: String) async throws -> [DrugInfo] {
        try await Task.sleep(for: .milliseconds(350))

        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty {
            return Self.catalogue
        }

        return Self.catalogue.filter {            $0.name.lowercased().contains(text)
                || ($0.synonym?.lowercased().contains(text) ?? false)
        }
    }

    func details(rxcui: String) async throws -> DrugInfo? {
        try await Task.sleep(for: .milliseconds(200))
        return Self.catalogue.first { $0.rxcui == rxcui }
    }

    func foodInteractions(for drugName: String) async throws -> [FoodInteraction] {
        try await Task.sleep(for: .milliseconds(250))
        return Self.interactions[drugName.lowercased()]?.sorted {
            $0.severity.order < $1.severity.order
        } ?? []
    }

    // MARK: - Sample data

    /// Real RxCUIs and real label text, so the screen shows something
    /// believable rather than "Lorem ipsum".
    private static let catalogue: [DrugInfo] = [
        DrugInfo(
            rxcui: "723", name: "Amoxicillin", synonym: "Amoxil", form: "Capsule",
            purpose: "A penicillin antibiotic used for bacterial infections of the chest, ear, throat and urinary tract.",
            warnings: "Tell your doctor about any penicillin allergy. Finish the full course even if you feel better.",
            dosageGuidance: "Usually 250–500 mg every 8 hours, or as prescribed."
        ),
        DrugInfo(
            rxcui: "6809", name: "Metformin", synonym: "Glucophage", form: "Tablet",
            purpose: "Lowers blood sugar in type 2 diabetes by reducing glucose production in the liver.",
            warnings: "Stop and seek help if you develop muscle pain, trouble breathing or unusual tiredness.",
            dosageGuidance: "Taken with meals to reduce stomach upset."
        ),
        DrugInfo(
            rxcui: "1191", name: "Aspirin", synonym: "Acetylsalicylic acid", form: "Tablet",
            purpose: "Relieves pain and inflammation; low doses are used to reduce the risk of heart attack and stroke.",
            warnings: "Can irritate the stomach. Not for children with fever.",
            dosageGuidance: "Take with food or a full glass of water."
        ),
        DrugInfo(
            rxcui: "161", name: "Paracetamol", synonym: "Acetaminophen", form: "Tablet",
            purpose: "Reduces pain and fever.",
            warnings: "Do not exceed the daily maximum. Overdose causes serious liver damage.",
            dosageGuidance: "500–1000 mg every 4–6 hours, maximum 4 g a day."
        ),
        DrugInfo(
            rxcui: "11289", name: "Warfarin", synonym: "Coumadin", form: "Tablet",
            purpose: "A blood thinner that prevents clots forming.",
            warnings: "Many foods and medicines change how it works. Keep your diet consistent and attend blood tests.",
            dosageGuidance: "Dose is set individually from blood-test results."
        ),
        DrugInfo(
            rxcui: "42463", name: "Vitamin D3", synonym: "Cholecalciferol", form: "Tablet",
            purpose: "Supplements vitamin D to support bone health.",
            warnings: "Very high doses over long periods can raise blood calcium.",
            dosageGuidance: "Often taken weekly or monthly at high strength."
        ),
    ]

    /// Food–drug interactions. This is the part patients actually get wrong,
    /// and the reason the app is called MedicFood.
    private static let interactions: [String: [FoodInteraction]] = [
        "warfarin": [
            FoodInteraction(food: "Leafy greens (spinach, kale)", effect: "High vitamin K reduces the effect. Keep intake steady rather than avoiding them.", severity: .caution),
            FoodInteraction(food: "Cranberry juice", effect: "May increase bleeding risk.", severity: .avoid),
            FoodInteraction(food: "Alcohol", effect: "Changes how quickly the drug is cleared.", severity: .avoid),
        ],
        "metformin": [
            FoodInteraction(food: "Alcohol", effect: "Raises the risk of lactic acidosis and low blood sugar.", severity: .avoid),
            FoodInteraction(food: "High-fibre meals", effect: "Can slightly reduce absorption.", severity: .minor),
        ],
        "amoxicillin": [
            FoodInteraction(food: "Dairy", effect: "Generally fine with amoxicillin, unlike some other antibiotics.", severity: .minor),
        ],
        "aspirin": [
            FoodInteraction(food: "Alcohol", effect: "Increases the risk of stomach bleeding.", severity: .avoid),
            FoodInteraction(food: "An empty stomach", effect: "Take with food to reduce irritation.", severity: .caution),
        ],
        "paracetamol": [
            FoodInteraction(food: "Alcohol", effect: "Raises the risk of liver damage.", severity: .avoid),
        ],
    ]
}
