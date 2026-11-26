import CoreData
import PDFKit
@testable import FreakLog
import UIKit
import XCTest

@MainActor
final class ExperienceReportTests: XCTestCase {
    func testTripDraftOmitsIdentifiersAndPutsTheAuthorsNotesInTheBody() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        let experience = Experience.create(at: start, in: context)
        experience.text = "I was already feeling curious.\n\nI made a few notes."
        let ingestion = Ingestion(context: context)
        ingestion.experience = experience
        ingestion.time = start
        ingestion.endTime = start.addingTimeInterval(120)
        ingestion.consumerName = "Private participant"
        ingestion.substanceName = "Caffeine"
        ingestion.setLocation(Location(name: "Private address", longitude: nil, latitude: nil))

        let note = TimedNote(context: context)
        note.experience = experience
        note.time = start.addingTimeInterval(-60)
        note.note = "Before the first entry"
        let rating = ShulginRating(context: context)
        rating.experience = experience
        rating.time = start.addingTimeInterval(60)
        rating.option = ShulginRatingOption.plus.rawValue

        let report = ExperienceReport.markdown(for: experience, includesRatings: true)
        XCTAssertTrue(report.hasPrefix("# Experience Report\n"))
        XCTAssertFalse(report.contains(experience.titleUnwrapped))
        XCTAssertFalse(report.contains("Private participant"))
        XCTAssertFalse(report.contains("Private address"))
        XCTAssertTrue(report.contains("Participant 1"))
        XCTAssertFalse(report.contains(" · "))
        XCTAssertFalse(report.contains("**"))
        XCTAssertTrue(report.contains("T+0 marks the first recorded ingestion."))
        let first = try XCTUnwrap(report.range(of: "T-1m - Before the first entry"))
        let second = try XCTUnwrap(report.range(of: "T+0 to T+2m - Caffeine"))
        let third = try XCTUnwrap(report.range(of: "T+1m - Rated"))
        XCTAssertLessThan(second.lowerBound, first.lowerBound)
        XCTAssertLessThan(first.lowerBound, third.lowerBound)
        XCTAssertTrue(report.contains("I was already feeling curious.\n\nI made a few notes."))

        let options = ExperienceReport.Options(includesTitle: true, includesDates: true, includesLocations: true, includesNames: true)
        let optedIn = ExperienceReport.markdown(for: experience, options: options, includesRatings: false)
        XCTAssertTrue(optedIn.contains(experience.titleUnwrapped))
        XCTAssertTrue(optedIn.contains(start.formatted(date: .abbreviated, time: .shortened)))
        XCTAssertTrue(optedIn.contains("Private participant"))
        XCTAssertTrue(optedIn.contains("Private address"))
        XCTAssertFalse(optedIn.contains("Rating"))
    }

    func testFirstTimedEntryAnchorsReportWithoutIngestions() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        let experience = Experience.create(at: start, in: context)
        let note = TimedNote(context: context)
        note.experience = experience
        note.note = "Starting note"
        note.time = start.addingTimeInterval(1_800)

        let report = ExperienceReport.markdown(for: experience, includesRatings: false)
        XCTAssertTrue(report.contains("T+0 marks the first timed entry."))
        XCTAssertTrue(report.contains("T+0 - Starting note"))
        XCTAssertFalse(report.contains("Recorded Doses"))
    }

    func testSelectiveReportExportsOnlySelectedRowsAndOptedInIdentifiers() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let range = DateInterval(start: start, duration: 1_800)
        let experience = Experience.create(at: start, title: "Private title", in: context)
        let ingestion = Ingestion(context: context)
        ingestion.experience = experience
        ingestion.time = start
        ingestion.substanceName = "Caffeine"
        ingestion.consumerName = "Private participant"
        ingestion.administrationSite = "Private site"
        ingestion.setLocation(Location(name: "Private location", longitude: nil, latitude: nil))

        let excludedIngestion = Ingestion(context: context)
        excludedIngestion.experience = experience
        excludedIngestion.time = start
        excludedIngestion.substanceName = "Excluded substance"

        let includedNote = TimedNote(context: context)
        includedNote.experience = experience
        includedNote.time = start
        includedNote.note = "Inside period"
        let excludedNote = TimedNote(context: context)
        excludedNote.experience = experience
        excludedNote.time = range.end
        excludedNote.note = "Outside period"

        let privateSummary = SelectiveJournalReport(
            kind: .journal, ingestions: [ingestion], experiences: [experience], range: range, options: .init())
        for value in [
            "Private title", "Private participant", "Private site", "Private location",
            "Excluded substance", "Inside period", "Outside period",
        ] {
            XCTAssertFalse(privateSummary.markdown.contains(value), value)
        }
        XCTAssertTrue(privateSummary.markdown.contains("Unknown amount"))
        XCTAssertTrue(privateSummary.markdown.contains("Day 1"))

        let summary = SelectiveJournalReport(
            kind: .clinician, ingestions: [ingestion], experiences: [experience], range: range,
            options: .init(exactDates: true, notes: true, locations: true, names: true, sites: true))
        XCTAssertTrue(summary.markdown.hasPrefix("# Clinician Summary"))
        XCTAssertTrue(summary.markdown.contains("Self-reported"))
        XCTAssertTrue(summary.markdown.contains("## Recorded Use\n\n### Caffeine"))
        XCTAssertFalse(summary.markdown.contains(" · "))
        XCTAssertTrue(summary.markdown.contains("Private title"))
        XCTAssertTrue(summary.markdown.contains("Private participant"))
        XCTAssertTrue(summary.markdown.contains("Private location"))
        XCTAssertTrue(summary.markdown.contains("Private site"))
        XCTAssertTrue(summary.markdown.contains("Inside period"))
        XCTAssertFalse(summary.markdown.contains("Outside period"))
        XCTAssertFalse(summary.markdown.contains("Excluded substance"))
    }

    func testRenderedReportFilesUseReviewedCopyAndOmitPrivateFields() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let experience = Experience.create(at: start, title: "Private party", in: context)
        let ingestion = Ingestion(context: context)
        ingestion.experience = experience
        ingestion.time = start
        ingestion.substanceName = "Caffeine"
        ingestion.consumerName = "Private participant"
        ingestion.administrationSite = "Private site"
        ingestion.setLocation(Location(name: "Private location", longitude: 4, latitude: 5))

        let report = SelectiveJournalReport(kind: .clinician, ingestions: [ingestion], experiences: [experience],
                                           range: nil, options: .init())
        let reviewed = report.markdown + "\nReviewed text"
        let pdf = try XCTUnwrap(PDFDocument(data: ReportRendering.clinicianPDF(reviewed).data))
        let pdfText = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(pdfText.contains("Reviewed text"))
        XCTAssertTrue(pdfText.contains("Caffeine"))
        for privateField in ["Private party", "Private participant", "Private site", "Private location"] {
            XCTAssertFalse(pdfText.contains(privateField), privateField)
        }

        let image = try ReportRendering.timelineImage(
            ExperienceReport.markdown(for: experience, includesRatings: false)
        )
        XCTAssertEqual(Array(image.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertNotNil(UIImage(data: image.data))
    }

    func testPDFPaginationRetainsLastReviewedEntry() throws {
        let lines = (1...200).map { "- Reviewed line \($0)" }
        let pdf = try XCTUnwrap(PDFDocument(data: ReportRendering.clinicianPDF(lines.joined(separator: "\n")).data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.page(at: pdf.pageCount - 1)?.string?.contains("Reviewed line 200") == true)
    }

    func testUnconfirmedEntriesRequireOptInAndAreLabeledInReports() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let experience = Experience.create(at: .now, in: context)
        let confirmed = Ingestion(context: context)
        confirmed.experience = experience
        confirmed.time = .now
        confirmed.substanceName = "Caffeine"
        let pending = Ingestion(context: context)
        pending.experience = experience
        pending.time = .now
        pending.substanceName = "Pending example"
        pending.isUnconfirmed = true

        let trip = ExperienceReport.markdown(for: experience, includesRatings: false)
        XCTAssertTrue(trip.contains("Caffeine"))
        XCTAssertFalse(trip.contains("Pending example"))
        let reviewedTrip = ExperienceReport.markdown(
            for: experience, options: .init(includesUnconfirmed: true), includesRatings: false
        )
        XCTAssertTrue(reviewedTrip.contains("Pending example"))
        XCTAssertTrue(reviewedTrip.contains("unconfirmed"))

        for kind in [SelectiveExportScreen.Kind.journal, .clinician] {
            let report = SelectiveJournalReport(
                kind: kind, ingestions: [confirmed, pending], experiences: [experience], range: nil, options: .init()
            )
            XCTAssertTrue(report.markdown.contains("1 ingestion."))
            XCTAssertFalse(report.markdown.contains("Pending example"))
            XCTAssertTrue(report.excluded.contains("Unconfirmed ingestions"))
            let reviewed = SelectiveJournalReport(
                kind: kind, ingestions: [confirmed, pending], experiences: [experience],
                range: nil, options: .init(unconfirmed: true)
            )
            XCTAssertTrue(reviewed.markdown.contains("Pending example"))
            XCTAssertTrue(reviewed.markdown.contains("unconfirmed"))
            XCTAssertTrue(reviewed.included.contains("Unconfirmed ingestions"))
        }
    }

    func testStandaloneSubstancePresetCopiesDefinitionUnderReviewedName() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let existing = CustomSubstanceCodable(name: "My custom", units: "g", description: "Local definition")
            .insert(into: context)
        var oral = CustomRoaCodable(administrationRoute: .oral, doseUnits: "mg")
        oral.commonDose = 1
        let preset = try JournalPreset(customSubstance: .init(name: "MY CUSTOM", units: "mg",
                                                             description: "Incoming definition", roas: [oral]))
        let restored = try JSONDecoder().decode(JournalPreset.self, from: preset.exportFile().data)
        XCTAssertEqual(try restored.availableName(in: context), "MY CUSTOM (Copy)")
        XCTAssertThrowsError(try restored.importInto(context, as: "My custom", keepLocalDefinitions: false))
        _ = try restored.importInto(context, as: "Imported custom", keepLocalDefinitions: false)

        let all = try context.fetch(PersistenceController.customSubstancesRequest())
        let imported = try XCTUnwrap(all.first { $0.nameUnwrapped == "Imported custom" })
        XCTAssertEqual(CustomSubstanceCodable(imported).roas, [oral])
        XCTAssertEqual(existing.explanationUnwrapped, "Local definition")
        XCTAssertEqual(try context.count(for: Experience.fetchRequest()), 0)
    }

    func testPaletteReviewPreservesConflictingColorsUnlessSelected() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let caffeine = CompanionCodable(substanceName: "Caffeine", color: .blue)
            .insert(into: context)
        let preset = try JournalPreset(palette: [
            .init(substanceName: "Caffeine", color: .orange),
            .init(substanceName: "Missing custom substance", color: .purple),
        ])
        let data = try preset.exportFile().data
        let restored = try JSONDecoder().decode(JournalPreset.self, from: data)
        let review = try restored.reviewPalette(in: context)
        XCTAssertTrue(review[0].hasConflict)
        XCTAssertFalse(review[1].isKnownSubstance)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("isHiddenInTimeline"))
        try restored.importPalette(review, replacing: [], in: context)
        XCTAssertEqual(caffeine.color, .blue)
        try restored.importPalette(review, replacing: ["Caffeine"], in: context)
        XCTAssertEqual(caffeine.color, .orange)
        XCTAssertEqual(try context.count(for: SubstanceCompanion.fetchRequest()), 1)
        XCTAssertThrowsError(try restored.importPalette(review, replacing: ["Caffeine"], in: context))
    }
}
