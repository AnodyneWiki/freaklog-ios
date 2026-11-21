@testable import FreakLog
import XCTest

final class CustomRoaTests: XCTestCase {
    private var baseline: CustomRoaCodable {
        var values = CustomRoaCodable(administrationRoute: .oral, doseUnits: "mg")
        values.lightDose = 10
        values.commonDose = 20
        values.onsetLow = 20
        values.onsetHigh = 40
        values.peakLow = 60
        values.peakHigh = 120
        return values
    }

    func testFillsEmptyPhasesAndDoseLevels() {
        var override = CustomRoaCodable(administrationRoute: .oral, doseUnits: "mg")
        override.commonDose = 25
        override.peakLow = 90
        let filled = override.fillingGaps(from: baseline)
        XCTAssertEqual(filled.lightDose, 10)
        XCTAssertEqual(filled.commonDose, 25)
        XCTAssertEqual(filled.onsetLow, 20)
        XCTAssertEqual(filled.onsetHigh, 40)
        // A phase with one bound stays a fixed time
        XCTAssertEqual(filled.peakLow, 90)
        XCTAssertNil(filled.peakHigh)
    }

    func testLeavesPartsTheOverrideDoesNotSet() {
        var override = CustomRoaCodable(administrationRoute: .oral, doseUnits: "µg")
        override.commonDose = 300
        let filled = override.fillingGaps(from: baseline)
        // Other units: the PsychonautWiki numbers don't apply
        XCTAssertNil(filled.lightDose)
        // No duration in the override: PsychonautWiki keeps providing it
        XCTAssertNil(filled.onsetLow)
    }
}
