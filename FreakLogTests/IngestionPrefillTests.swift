import XCTest
@testable import FreakLog

@MainActor
final class IngestionPrefillTests: XCTestCase {
    private let substance = AddIngestionSubstance.custom(name: "Shortcut Test Item", units: "servings")

    func testDistinctCustomDefinitionsRequireAChoice() {
        let request = prefill(substance: "  SHORTCUT TEST ITEM  ")
        let first = CustomSubstanceModel(name: substance.name, description: "", units: "servings")
        let second = CustomSubstanceModel(name: substance.name, description: "", units: "drops")

        XCTAssertEqual(request.matchSubstance(in: [first], isEyeOpen: false), substance)
        XCTAssertNil(request.matchSubstance(in: [first, second], isEyeOpen: false))
    }

    func testChangingSubstanceOrRouteDoesNotApplyTheAmount() {
        let request = prefill(substance: substance.name, route: " Oral ", amount: 2, unit: "servings")
        let oral = SubstanceAndRoute(substance: substance, administrationRoute: .oral)
        XCTAssertEqual(request.doseEditor(for: oral, matchedSubstance: substance).amount, 2)

        let otherRoute = SubstanceAndRoute(substance: substance, administrationRoute: .sublingual)
        XCTAssertNil(request.doseEditor(for: otherRoute, matchedSubstance: substance).amount)
        XCTAssertNil(request.doseEditor(for: oral, matchedSubstance: nil).amount)
    }

    func testAmountRequiresAnExplicitUnitAndMustBeFiniteAndPositive() {
        let arguments = SubstanceAndRoute(substance: substance, administrationRoute: .oral)
        let request = prefill(amount: 2)
        XCTAssertNil(request.doseEditor(for: arguments, matchedSubstance: nil).amount)
        XCTAssertNil(prefill(amount: .infinity, unit: "mg").doseEditor(for: arguments, matchedSubstance: nil).amount)
        XCTAssertNil(prefill(amount: -1, unit: "mg").doseEditor(for: arguments, matchedSubstance: nil).amount)
        let valid = prefill(amount: 2, unit: "mcg").doseEditor(for: arguments, matchedSubstance: nil)
        XCTAssertEqual(valid.amount, 2)
        XCTAssertEqual(valid.units, "µg")
    }

    func testOpeningAShortcutDoesNotReplaceAnOpenDraft() {
        let navigator = Navigator()
        let first = prefill(note: "Original")
        let second = prefill(note: "New")

        XCTAssertTrue(navigator.prefillIngestion(first))
        XCTAssertFalse(navigator.prefillIngestion(second))
        XCTAssertEqual(navigator.ingestionPrefill?.note, "Original")

        navigator.isShowingAddIngestionSheet = false
        XCTAssertTrue(navigator.prefillIngestion(second))
        XCTAssertEqual(navigator.ingestionPrefill?.note, "New")
    }

    private func prefill(
        substance: String? = nil,
        route: String? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        note: String? = nil
    ) -> IngestionPrefill {
        IngestionPrefill(substance: substance, route: route, amount: amount, unit: unit, time: nil, note: note)
    }
}
