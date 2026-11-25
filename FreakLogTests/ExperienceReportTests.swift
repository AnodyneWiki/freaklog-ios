import CoreData
@testable import FreakLog
import XCTest

@MainActor
final class ExperienceReportTests: XCTestCase {
    func testDefaultDraftOmitsStructuredIdentifiersAndKeepsEventsInOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        let experience = Experience.create(at: start, in: context)
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
        XCTAssertTrue(report.contains("T+0 is the first recorded ingestion."))
        let first = try XCTUnwrap(report.range(of: "T-00:01:00** · Note"))
        let second = try XCTUnwrap(report.range(of: "T+00:00:00 to T+00:02:00** · Caffeine"))
        let third = try XCTUnwrap(report.range(of: "T+00:01:00** · Rating"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        XCTAssertLessThan(second.lowerBound, third.lowerBound)

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
        XCTAssertTrue(report.contains("T+0 is the first timed entry."))
        XCTAssertTrue(report.contains("T+00:00:00** · Note · Starting note"))
        XCTAssertFalse(report.contains("Ingestion Summary"))
    }
}
