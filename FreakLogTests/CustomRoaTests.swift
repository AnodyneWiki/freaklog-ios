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

    func testEmptyValuesNeedNoRow() {
        let empty = CustomRoaCodable(administrationRoute: .oral)
        XCTAssertFalse(empty.needsSavedRow(hasExistingRow: true, baseline: baseline, psychonautWiki: baseline))
        XCTAssertFalse(empty.needsSavedRow(hasExistingRow: false, baseline: baseline, psychonautWiki: baseline))
    }

    func testExistingRowStaysUnlessItMatchesPsychonautWiki() {
        let psychonautWiki = CustomRoaCodable(administrationRoute: .oral)
        // The baseline here came from the AnodyneWiki cache: the user's row matching it must survive
        XCTAssertTrue(baseline.needsSavedRow(hasExistingRow: true, baseline: baseline, psychonautWiki: psychonautWiki))
        XCTAssertFalse(baseline.needsSavedRow(hasExistingRow: true, baseline: baseline, psychonautWiki: baseline))
    }

    func testNewRowOnlyWhenValuesDifferFromTheForm() {
        let psychonautWiki = CustomRoaCodable(administrationRoute: .oral)
        // Opening the editor fills the form with the baseline, which must not create a row
        XCTAssertFalse(baseline.needsSavedRow(hasExistingRow: false, baseline: baseline, psychonautWiki: psychonautWiki))
        var edited = baseline
        edited.commonDose = 25
        XCTAssertTrue(edited.needsSavedRow(hasExistingRow: false, baseline: baseline, psychonautWiki: psychonautWiki))
    }
}
