import CoreData
@testable import FreakLog
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
}
