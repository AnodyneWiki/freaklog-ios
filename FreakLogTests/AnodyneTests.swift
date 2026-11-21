@testable import FreakLog
import XCTest

// Parses trimmed copies of real AnodyneWiki API responses
final class AnodyneTests: XCTestCase {
    private func fixture(_ key: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Anodyne", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(json[key] as? [String: Any])
    }

    func testReadsDoseTiersPerRoute() throws {
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        XCTAssertEqual(mdma.title, "3,4-Methylenedioxymethamphetamine")
        XCTAssertEqual(mdma.commonName, "MDMA")
        let oral = try XCTUnwrap(mdma.dosing.first { $0.route == .oral })
        XCTAssertEqual(oral.light?.upper, 74.6)
        XCTAssertEqual(oral.common?.lower, 74.6)
        XCTAssertEqual(oral.common?.upper, 100)
        XCTAssertEqual(oral.extreme?.lower, 200)
        XCTAssertEqual(oral.unit, "mg")
        XCTAssertEqual(oral.totalEntries, 61)
        XCTAssertEqual(mdma.dosing.first { $0.method == "Intrarectal" }?.route, .rectal)
        XCTAssertEqual(mdma.durationOfAction, "3 – 6 hours")
        XCTAssertFalse(mdma.erowidReports.isEmpty)
        XCTAssertEqual(mdma.redditReports.count, 2)
        XCTAssertFalse(mdma.reagents.isEmpty)
    }

    func testDoseValuesStartAtEachTier() throws {
        let mdma = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("mdma")))
        let values = try XCTUnwrap(mdma.dosing.first { $0.route == .oral }).doseValues(for: .oral)
        XCTAssertNil(values.lightDose)
        XCTAssertEqual(values.commonDose, 74.6)
        XCTAssertEqual(values.strongDose, 100)
        XCTAssertEqual(values.heavyDose, 120)
        XCTAssertEqual(values.doseUnits, "mg")
    }

    func testCleansHtmlAndReadsVaryingFields() throws {
        let amphetamine = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("amphetamine")))
        XCTAssertEqual(amphetamine.classes, ["Stimulant"])
        XCTAssertEqual(amphetamine.abbreviations, ["Speed"])
        XCTAssertEqual(
            amphetamine.durationOfAction,
            "Immediate release dosing: 3 – 6 hours Extended release dosing: 8 – 12 hours"
        )
        XCTAssertTrue(amphetamine.effectGroups.contains { $0.name == "Physical Effects" && $0.effects.contains("Stimulation") })
    }

    func testUnknownSubstanceIsNotFound() throws {
        XCTAssertNil(AnodyneSubstance(apiJSON: try fixture("notFound")))
    }

    func testIndexEntries() throws {
        let entries = (try fixture("index")["Entries"] as? [[String: Any]] ?? []).compactMap(AnodyneIndexEntry.init(apiJSON:))
        // Oxytocin is marked NoBuild and has no page
        XCTAssertEqual(entries.map(\.title).sorted(), ["3,4-Methylenedioxymethamphetamine", "Amphetamine", "Ketamine"])
        let ketamine = try XCTUnwrap(entries.first { $0.title == "Ketamine" })
        XCTAssertTrue(ketamine.matches("k"))
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.title == "Amphetamine" }).matches("speed"))
    }

    func testMapsAdministrationMethods() {
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Insufflated"), .insufflated)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Sublingual"), .sublingual)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Intravenous"), .intravenous)
        XCTAssertEqual(AnodyneSubstance.route(forMethod: "Vaporized"), .inhaled)
        XCTAssertNil(AnodyneSubstance.route(forMethod: "Ocular"))
    }
}
