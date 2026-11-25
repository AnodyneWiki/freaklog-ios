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
            var legacySelection = try XCTUnwrap(olderPin["selection"] as? [String: Any])
            legacySelection.removeValue(forKey: "substances")
            legacySelection.removeValue(forKey: "tags")
            legacySelection["substance"] = "Sample"
            legacySelection["tag"] = "Daily"
            olderPin["selection"] = legacySelection
            let data = try JSONSerialization.data(withJSONObject: [olderPin])
            let migrated = try XCTUnwrap(StatsPreferences.decode(data).first)
            XCTAssertEqual(migrated.id, pin.id)
            XCTAssertEqual(migrated.name, pin.name)
            XCTAssertEqual(migrated.metric, .ingestions)
            XCTAssertEqual(migrated.selection.period, selection.period)
            XCTAssertEqual(migrated.selection.substances, selection.substances)
            XCTAssertEqual(migrated.selection.tags, ["Daily"])
            XCTAssertEqual(migrated.selection.route, selection.route)
        }
    }

    func testPinnedBucketSurvivesRollingPeriodAdvancingAndFiltersNarrowIt() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let yesterday = now.addingTimeInterval(-86_400)
        let experience = Experience.create(at: yesterday, in: context)
        let first = makeIngestion(in: experience, at: yesterday, context: context)
        let second = makeIngestion(in: experience, at: yesterday, context: context)
        second.substanceName = "Example"
        let today = makeIngestion(in: experience, at: now, context: context)
        let entries = [first, second, today]
        let selection = StatsSelection(period: .last7Days)
        let records = StatsRecords(entries: entries, selection: selection, now: now, calendar: calendar)
        let bucket = try XCTUnwrap(records.buckets(for: .ingestions).first)
        let focused = records.selecting(bucket, for: .ingestions)
        let pinned = selection.focused(on: focused.range, metric: .ingestions, within: records.range)
        let restoredPin = try JSONDecoder().decode(StatsSelection.self, from: JSONEncoder().encode(pinned))
        let later = now.addingTimeInterval(14 * 86_400)
        let reopened = StatsRecords(entries: entries, selection: restoredPin, now: later, calendar: calendar)
        let narrowed = StatsRecords(entries: entries, selection: pinned.forSubstance("Sample"), now: later, calendar: calendar)

        XCTAssertEqual(reopened.entries, [first, second])
        XCTAssertEqual(narrowed.entries, [first])
    }

    func testMultiSelectAndGoalsUseOnlyConfirmedMatchingRecords() {
        let context = PersistenceController(inMemory: true).viewContext
        let experience = Experience.create(at: now, in: context)
        let first = makeIngestion(in: experience, at: now, context: context)
        first.dose = 2
        let second = makeIngestion(in: experience, at: now, context: context)
        second.substanceName = "Second"
        let excludedTag = makeIngestion(in: experience, at: now, context: context)
        excludedTag.substanceName = "Third"
        let unconfirmed = makeIngestion(in: experience, at: now, context: context)
        unconfirmed.dose = 50
        unconfirmed.isUnconfirmed = true
        let unknownAmount = makeIngestion(in: experience, at: now, context: context)
        let otherUnit = makeIngestion(in: experience, at: now, context: context)
        otherUnit.dose = 4
        otherUnit.units = "mL"
        let entries = [first, second, excludedTag, unconfirmed, unknownAmount, otherUnit]

        var selection = StatsSelection(period: .last7Days)
        selection.substances = ["Sample", "Second", "Third"]
        selection.tags = ["a", "b"]
        let tags = [
            "Sample": PersonalSubstanceTags(["A"]),
            "Second": PersonalSubstanceTags(["B"]),
            "Third": PersonalSubstanceTags(["C"])
        ]
        let records = StatsRecords(entries: entries, selection: selection, now: now, calendar: calendar, tags: tags)
        XCTAssertEqual(records.entries, [first, second, unknownAmount, otherUnit])

        let goal = StatsGoal(substance: "Sample", metric: .amount, target: 10, unit: "mg")
        let progress = goal.progress(in: entries, endingAt: now, calendar: calendar)
        XCTAssertEqual(progress.value, 2)
        XCTAssertEqual(progress.entries, [first])
        XCTAssertEqual(progress.unknown, [unknownAmount])
        XCTAssertEqual(progress.otherUnits, [otherUnit])
    }

    func testExperienceDrillDownKeepsTheOriginalCohortAfterChangingSubstance() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let day = calendar.startOfDay(for: now)
        let yesterday = day.addingTimeInterval(-86_400)
        let start = day.addingTimeInterval(600)
        let earlierExperience = Experience.create(at: yesterday, in: context)
        let earlierAnchor = makeIngestion(in: earlierExperience, at: yesterday, context: context)
        let earlierFollowup = makeIngestion(in: earlierExperience, at: start, context: context)
        earlierFollowup.substanceName = "Example"
        let selectedExperience = Experience.create(at: start, in: context)
        let selectedAnchor = makeIngestion(in: selectedExperience, at: start, context: context)
        let selectedFollowup = makeIngestion(in: selectedExperience, at: start, context: context)
        selectedFollowup.substanceName = "Example"
        let entries = [earlierAnchor, earlierFollowup, selectedAnchor, selectedFollowup]
        let selection = StatsSelection(period: .last7Days)
        let records = StatsRecords(entries: entries, selection: selection, now: now, calendar: calendar)
        let bucket = try XCTUnwrap(records.buckets(for: .experiences).last)
        let focused = records.selecting(bucket, for: .experiences)
        let drillDown = selection.focused(on: focused.range, metric: .experiences, within: records.range).forSubstance("Example")
        let shown = StatsRecords(entries: entries, selection: drillDown, now: now, calendar: calendar)
        XCTAssertEqual(shown.entries, [selectedFollowup])
    }

    func testAlongsideRequiresTheSameExperienceAndConsumer() {
        let context = PersistenceController(inMemory: true).viewContext
        let experience = Experience.create(at: now, in: context)
        let anchor = makeIngestion(in: experience, at: now, context: context)
        let alongside = makeIngestion(in: experience, at: now, context: context)
        alongside.substanceName = "Alongside"
        let someoneElse = makeIngestion(in: experience, at: now, context: context)
        someoneElse.substanceName = "Different Consumer"
        someoneElse.consumerName = "Someone else"
        let another = makeIngestion(in: Experience.create(at: now, in: context), at: now, context: context)
        another.substanceName = "Another Experience"
        var selection = StatsSelection(period: .allTime, person: .everyone)
        selection.alongside = "Sample"
        let records = StatsRecords(
            entries: [anchor, alongside, someoneElse, another], selection: selection, now: now, calendar: calendar
        )
        XCTAssertEqual(records.entries, [alongside])
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

    func testCustomDatesIncludeTheWholeLastDayAndKeepBucketCountsInSync() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 3)))
        let lastDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 29, to: firstDay))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: lastDay))
        let experience = Experience.create(at: firstDay, in: context)
        let first = makeIngestion(in: experience, at: firstDay, context: context)
        let last = makeIngestion(in: experience, at: nextDay.addingTimeInterval(-1), context: context)
        let outside = makeIngestion(in: experience, at: nextDay, context: context)
        let records = StatsRecords(
            entries: [first, last, outside],
            selection: StatsSelection(period: .custom, customStart: firstDay, customEnd: lastDay),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(records.entries, [first, last])
        XCTAssertEqual(records.experiences.count, 1)
        XCTAssertEqual(records.daysLogged, 2)
        let buckets = records.buckets(for: .ingestions)
        XCTAssertEqual(records.chartDomain(covering: buckets), firstDay...nextDay)
        let focused = records.selecting(try XCTUnwrap(buckets.last), for: .ingestions)
        XCTAssertEqual(focused.entries, [last])
        XCTAssertEqual(focused.experiences.count, 1)
        XCTAssertEqual(focused.daysLogged, 1)

        let allTime = StatsRecords(
            entries: [first, last], selection: StatsSelection(period: .allTime), now: now, calendar: calendar
        )
        let year = try XCTUnwrap(calendar.dateInterval(of: .year, for: firstDay))
        XCTAssertEqual(allTime.chartDomain(covering: allTime.buckets(for: .ingestions)), year.start...year.end)
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
