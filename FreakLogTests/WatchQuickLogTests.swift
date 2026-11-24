import XCTest
@testable import FreakLog

final class WatchQuickLogTests: XCTestCase {
  func testDoseStepTakesAboutTwentyTurns() {
    XCTAssertEqual(WatchQuickLog.doseStep(around: 100), 5)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 250), 10)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 10), 0.5, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 1.5), 0.1, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 3), 0.2, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 0), 1)
  }

  func testCrownStartsAtTheLatestKnownDose() {
    let doses = [
      WatchDose(amount: nil, isEstimate: false, standardDeviation: nil),
      WatchDose(amount: 80, isEstimate: false, standardDeviation: nil),
      WatchDose(amount: 120, isEstimate: false, standardDeviation: nil),
    ]
    XCTAssertEqual(suggestion(doses: doses).typicalDose, 80)
    XCTAssertEqual(suggestion(doses: []).typicalDose, 0)
  }

  func testCustomUnitsMoveByHalfUnits() {
    let doses = [WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)]
    XCTAssertEqual(suggestion(customUnit: pill, doses: doses).doseStep, 0.5)
  }

  func testDescribesDoses() {
    let suggestion = suggestion(doses: [])
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: false, standardDeviation: nil)), "100 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: true, standardDeviation: nil)), "~100 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: true, standardDeviation: 10)), "100±10 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: nil, isEstimate: false, standardDeviation: nil)), "Unknown dose")
    XCTAssertNil(suggestion.calculatedDescription(of: WatchDose(amount: 100, isEstimate: false, standardDeviation: nil)))
  }

  func testDescribesCustomUnitDoses() {
    let suggestion = suggestion(customUnit: pill, doses: [])
    let one = WatchDose(amount: 1, isEstimate: false, standardDeviation: nil)
    let two = WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)
    XCTAssertEqual(suggestion.description(of: one), "1 pill")
    XCTAssertEqual(suggestion.description(of: two), "2 pills")
    XCTAssertEqual(suggestion.calculatedDescription(of: two), "240 mg")
    let estimated = WatchDose(amount: 1.5, isEstimate: true, standardDeviation: nil)
    XCTAssertEqual(suggestion.calculatedDescription(of: estimated), "~180 mg")
  }

  func testLogRequestRoundTrips() throws {
    let request = WatchLogRequest(
      id: UUID(),
      suggestion: suggestion(customUnit: pill, doses: [WatchDose(amount: 2, isEstimate: true, standardDeviation: 0.5)]),
      dose: WatchDose(amount: 1.5, isEstimate: false, standardDeviation: nil),
      time: Date(timeIntervalSince1970: 1_700_000_000))
    let data = try WatchQuickLog.encode(request)
    XCTAssertEqual(WatchQuickLog.decode(WatchLogRequest.self, from: data), request)
    XCTAssertNil(WatchQuickLog.decode(WatchLogRequest.self, from: "not data"))
  }

  func testDescribesFormulationAmounts() {
    let formulation = formulationSuggestion()
    let two = WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)
    XCTAssertEqual(formulation.description(of: two), "2×")
    XCTAssertEqual(formulation.calculatedDescription(of: two), "200±20 mg MDMA, Unknown dose Caffeine")
    XCTAssertEqual(formulation.doseStep, 0.5)
    let component = formulation.formulation?.components.first
    XCTAssertEqual(component?.dose(for: 1.5), WatchDose(amount: 150, isEstimate: true, standardDeviation: 15))
  }

  func testFormulationRequestsKnowAllTheirIngestions() throws {
    let request = WatchLogRequest(
      id: UUID(),
      suggestion: formulationSuggestion(),
      dose: WatchDose(amount: 1, isEstimate: false, standardDeviation: nil),
      time: Date(timeIntervalSince1970: 1_700_000_000))
    let identifiers = request.ingestionIdentifiers
    XCTAssertEqual(identifiers.count, 2)
    XCTAssertEqual(identifiers.first, request.id)
    XCTAssertEqual(Set(identifiers).count, 2)
    let decoded = try XCTUnwrap(WatchQuickLog.decode(WatchLogRequest.self, from: WatchQuickLog.encode(request)))
    XCTAssertEqual(decoded, request)
    XCTAssertEqual(decoded.ingestionIdentifiers, identifiers)
    XCTAssertEqual(
      WatchLogRequest(id: request.id, suggestion: suggestion(doses: []), dose: request.dose, time: request.time)
        .ingestionIdentifiers,
      [request.id])
  }

  private func formulationSuggestion() -> WatchSuggestion {
    WatchSuggestion(
      id: "x-coredata://formulation",
      substanceName: "Party pill",
      displayName: "Party pill",
      route: "oral",
      color: WatchColor(red: 1, green: 0, blue: 0.5),
      units: "",
      customUnit: nil,
      doses: [WatchDose(amount: 1, isEstimate: false, standardDeviation: nil)],
      formulation: WatchFormulation(components: [
        WatchFormulationComponent(
          substanceName: "MDMA",
          displayName: "MDMA",
          route: "oral",
          units: "mg",
          dose: WatchDose(amount: 100, isEstimate: true, standardDeviation: 10)),
        WatchFormulationComponent(
          substanceName: "Caffeine",
          displayName: "Caffeine",
          route: "oral",
          units: "mg",
          dose: WatchDose(amount: nil, isEstimate: false, standardDeviation: nil)),
      ]))
  }

  private let pill = WatchCustomUnit(
    id: "x-coredata://unit",
    name: "Pink pill",
    singular: "pill",
    plural: "pills",
    dosePerUnit: 120,
    isEstimate: false)

  private func suggestion(units: String = "mg", customUnit: WatchCustomUnit? = nil, doses: [WatchDose]) -> WatchSuggestion {
    WatchSuggestion(
      id: "MDMAoral",
      substanceName: "MDMA",
      displayName: "MDMA",
      route: "oral",
      color: WatchColor(red: 1, green: 0, blue: 0.5),
      units: units,
      customUnit: customUnit,
      doses: doses)
  }

}
