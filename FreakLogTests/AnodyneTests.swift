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
        // Shown in PsychonautWiki's form, without a threshold
        let roaDose = try XCTUnwrap(mdma.dosing.first { $0.route == .oral }?.roaDose)
        XCTAssertNil(roaDose.lightMin)
        XCTAssertEqual(roaDose.commonMin, 74.6)
        XCTAssertEqual(roaDose.strongMin, 100)
        XCTAssertEqual(roaDose.heavyMin, 120)
        XCTAssertEqual(roaDose.units, "mg")
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

    func testRemovesWikiMarkup() throws {
        let json: [String: Any] = [
            "Title": "Methylhexanamine",
            "Aliases": ["1,3-DMAA", "Benzeneethanamine, 4-fluoro-2,5-dimethoxy-"],
            "Scheduling": [
                [
                    "gov": "United States",
                    "schedule": "Unapproved drug; use is unlawful.{-{Efn|The N.D.A was withdrawn in 1983.|group=note}-} substance",
                ],
                ["gov": "US", "schedule": "List of Schedule II controlled substances (U.S.)|Schedule II substance"],
            ],
        ]
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: json))
        XCTAssertEqual(substance.scheduling.map(\.schedule), ["Unapproved drug; use is unlawful.", "Schedule II substance"])
        XCTAssertEqual(substance.aliases, ["1,3-DMAA"])
    }

    func testReadsUserNotes() throws {
        let notes = AnodyneUserNote.notes(fromUserJSON: try fixture("userNinerik"))
        XCTAssertEqual(notes.map(\.substanceName), ["Caffeine", "Amphetamine"])
        let caffeine = try XCTUnwrap(notes.first)
        XCTAssertEqual(caffeine.user, "ninerik")
        XCTAssertEqual(caffeine.routes.first?.name, "Oral")
        XCTAssertEqual(caffeine.routes.first?.dosage, "35–680 mg")
        XCTAssertEqual(caffeine.routesSummary, "Oral 35–680 mg")
        XCTAssertEqual(caffeine.effects.first, "light stimulation")
        XCTAssertTrue(caffeine.effects.contains("increased heart rate"))
        XCTAssertTrue(caffeine.effects.contains("addiction (since the start of 2026)"))
        XCTAssertTrue(caffeine.indications.contains("headache from Caffeine withdrawals"))
        XCTAssertEqual(caffeine.notes, ["Awful awful awful stimulant"])
        XCTAssertEqual(caffeine.userPageURL.absoluteString, "https://anodyne.wiki/user/ninerik")

        let mdma = try XCTUnwrap(AnodyneUserNote.notes(fromUserJSON: try fixture("userEmily")).first)
        XCTAssertEqual(mdma.routesSummary, "Oral 40–91 mg, Insufflated 22 mg")
        XCTAssertTrue(mdma.hasDetails)
    }

    func testRendersUserMarkup() {
        XCTAssertEqual("{sev 'strong'} {xeff 'appetite suppression'}".anodyneUserMarkupCleaned, "strong appetite suppression")
        XCTAssertEqual("{sub '2C-B'} and {class 'stimulant' 'stimulants'}".anodyneUserMarkupCleaned, "2C-B and stimulants")
        XCTAssertEqual("{p}Hello{Ep}{p}*there*{gt}{lt}{Ep}".anodyneUserMarkupCleaned, "Hello there><")
    }

    @MainActor
    func testReadsStructureAndFormula() throws {
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("methylhexanamine")))
        XCTAssertEqual(substance.formula, "C₇H₁₇N")
        XCTAssertEqual(substance.molarMass, "115.22 g/mol")
        let drawing = try XCTUnwrap(MoleculeDrawing.parse(try XCTUnwrap(substance.structureSVG)))
        XCTAssertEqual(drawing.viewBox, CGRect(x: 0, y: 0, width: 76.411, height: 26.88))
        // Bonds in the text color, the nitrogen label in its element color; the white background is left out
        XCTAssertTrue(drawing.shapes.contains { $0.stroke == .foreground })
        XCTAssertTrue(drawing.shapes.contains { $0.fill == .rgb(48.0 / 255, 80.0 / 255, 248.0 / 255) })
        XCTAssertFalse(drawing.shapes.contains { $0.path.boundingRect.width > 70 && $0.stroke == nil })
    }

    // Progesterone's structure is base64 encoded and draws its bonds as <line> elements
    @MainActor
    func testReadsBase64StructuresWithLines() throws {
        let substance = try XCTUnwrap(AnodyneSubstance(apiJSON: fixture("progesterone")))
        let drawing = try XCTUnwrap(MoleculeDrawing.parse(try XCTUnwrap(substance.structureSVG)))
        XCTAssertEqual(drawing.viewBox, CGRect(x: 0, y: 0, width: 125.909, height: 74.123))
        // 42 bond lines, 9 wedge and label paths; the white background rectangle is left out
        XCTAssertEqual(drawing.shapes.count, 51)
        XCTAssertTrue(drawing.shapes.contains { $0.stroke == .rgb(1, 13.0 / 255, 13.0 / 255) })
    }

    func testParsesRunTogetherPathNumbers() throws {
        let path = try XCTUnwrap(SVGPath.parse("m1.106 10.672.005 15.248M14.305 3.052l13.198-7.62h2v-1z"))
        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, 1.106, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 25.92, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 29.503, accuracy: 0.001)
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
