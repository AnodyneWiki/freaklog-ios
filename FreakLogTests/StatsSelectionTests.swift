import CoreData
import SwiftUI
import XCTest
@testable import FreakLog

@MainActor
final class StatsSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPinsForRemovedMetricsKeepTheirFilters() throws {
        let selection = StatsSelection(period: .last7Days, substance: "Sample", route: .oral)
        let pin = PinnedStatsView(name: "Sample history", metric: .ingestions, selection: selection)
        let encoded = try JSONEncoder().encode(pin)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        for metric in ["days", "amounts"] {
            var olderPin = original
            olderPin["metric"] = metric
            let data = try JSONSerialization.data(withJSONObject: [olderPin])
            let migrated = try XCTUnwrap(StatsPreferences.decode(data).first)
            XCTAssertEqual(migrated.id, pin.id)
            XCTAssertEqual(migrated.name, pin.name)
            XCTAssertEqual(migrated.metric, .ingestions)
            XCTAssertEqual(migrated.selection.period, selection.period)
            XCTAssertEqual(migrated.selection.substance, selection.substance)
            XCTAssertEqual(migrated.selection.route, selection.route)
        }
    }

    func testExperienceBucketsCountEachExperienceOnceAndKeepMatchingEntries() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let today = calendar.startOfDay(for: now)
        let twoDaysAgo = today.addingTimeInterval(-172_800)
        let yesterday = today.addingTimeInterval(-86_400)
        let first = Experience.create(at: twoDaysAgo, in: context)
        let second = Experience.create(at: yesterday, in: context)
        let firstEntry = makeIngestion(in: first, at: twoDaysAgo, context: context)
        let followupEntry = makeIngestion(in: first, at: yesterday, context: context)
        followupEntry.substanceName = "Another Substance"
        let secondEntry = makeIngestion(in: second, at: yesterday, context: context)
        let records = StatsRecords(
            entries: [firstEntry, followupEntry, secondEntry],
            selection: StatsSelection(period: .last7Days),
            now: now,
            calendar: calendar
        )
        let buckets = records.buckets(for: .experiences)

        XCTAssertEqual(records.experiences.count, 2)
        XCTAssertEqual(records.daysLogged, 2)
        XCTAssertEqual(buckets.map(\.count), [1, 1])
        XCTAssertEqual(records.ingestionContributions.map(\.count).reduce(0, +), 3)
        XCTAssertEqual(records.ingestionContributions.filter { $0.id.date == yesterday }.count, 2)
        let focused = records.selecting(try XCTUnwrap(buckets.first), for: .experiences)
        XCTAssertEqual(focused.experiences.map(\.experience), [first])
        XCTAssertEqual(Set(focused.entries.map(\.objectID)), [firstEntry.objectID, followupEntry.objectID])
    }

    func testEditedIngestionChangesSelectionWithoutChangingTheCount() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = now.addingTimeInterval(-86_400)
        let experience = Experience.create(at: start, in: context)
        let ingestion = makeIngestion(in: experience, at: start, context: context)
        let selection = StatsSelection(period: .last7Days, substance: "Sample", route: .oral, tag: "Daily")
        let tags = ["Sample": PersonalSubstanceTags(["DAILY"])]
        let makeRecords = {
            StatsRecords(entries: [ingestion], selection: selection, now: self.now, calendar: self.calendar, tags: tags)
        }

        XCTAssertEqual(makeRecords().entries, [ingestion])
        ingestion.time = start.addingTimeInterval(-14 * 86_400)
        XCTAssertTrue(makeRecords().entries.isEmpty)
        ingestion.time = start
        ingestion.administrationRoute = AdministrationRoute.transdermal.rawValue
        XCTAssertTrue(makeRecords().entries.isEmpty)

        let notification = Notification(name: .NSManagedObjectContextObjectsDidChange,
                                        userInfo: [NSUpdatedObjectsKey: Set<NSManagedObject>([ingestion])])
        XCTAssertTrue(StatsJournal<EmptyView>.affectsStats(notification))
    }

    func testGapsUseTheSameSubstanceAndPersonAcrossExperiences() {
        let context = PersistenceController(inMemory: true).viewContext
        let firstTime = now.addingTimeInterval(-3_600)
        let lastTime = now.addingTimeInterval(-600)
        let first = makeIngestion(in: Experience.create(at: firstTime, in: context), at: firstTime, context: context)
        let last = makeIngestion(in: Experience.create(at: lastTime, in: context), at: lastTime, context: context)
        let allPeople = StatsSelection(period: .last7Days, person: .everyone)
        func records() -> StatsRecords {
            StatsRecords(entries: [last, first], selection: allPeople, now: now, calendar: calendar)
        }

        XCTAssertEqual(records().gapsBetweenLogs.map(\.duration), [3_000])
        last.substanceName = "Different Substance"
        XCTAssertTrue(records().gapsBetweenLogs.isEmpty)
        last.substanceName = first.substanceName
        last.consumerName = "Another Person"
        XCTAssertTrue(records().gapsBetweenLogs.isEmpty)
    }

    func testAmountsKeepOriginalUnitsAndCountUnknowns() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let start = now.addingTimeInterval(-5)
        let experience = Experience.create(at: start, in: context)
        let known = makeIngestion(in: experience, at: start, context: context)
        known.dose = 2
        let another = makeIngestion(in: experience, at: start, context: context)
        another.dose = 3
        let differentUnit = makeIngestion(in: experience, at: start, context: context)
        differentUnit.dose = 10
        differentUnit.units = "mL"
        let unknown = makeIngestion(in: experience, at: start, context: context)
        let custom = makeIngestion(in: experience, at: start, context: context)
        custom.dose = 4
        custom.customUnit = CustomUnit(context: context)
        let otherPerson = makeIngestion(in: experience, at: start, context: context)
        otherPerson.consumerName = "Another Person"
        otherPerson.dose = 40

        let records = StatsRecords(
            entries: [known, another, differentUnit, unknown, custom, otherPerson],
            selection: StatsSelection(period: .allTime),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(records.unknownAmountCount, 1)
        XCTAssertEqual(records.amounts.count, 3)
        let milligrams = try XCTUnwrap(records.amounts.first { $0.key.unit == "mg" && $0.key.customUnitID == nil })
        XCTAssertEqual(milligrams.total, 5)
        XCTAssertEqual(milligrams.median, 2.5)
        XCTAssertEqual(records.amounts.first { $0.key.unit == "mL" }?.total, 10)
        XCTAssertEqual(records.amounts.first { $0.key.customUnitID != nil }?.total, 4)
    }

    private func makeIngestion(in experience: Experience, at time: Date, context: NSManagedObjectContext) -> Ingestion {
        let ingestion = Ingestion(context: context)
        ingestion.experience = experience
        ingestion.time = time
        ingestion.substanceName = "Sample"
        ingestion.administrationRoute = AdministrationRoute.oral.rawValue
        ingestion.units = "mg"
        return ingestion
    }
}
