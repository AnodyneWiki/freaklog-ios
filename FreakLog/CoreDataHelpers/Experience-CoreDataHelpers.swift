import CoreData
import SwiftUI

extension Experience: Comparable {
    // A new experience starting at the given time, titled with its date unless a title is entered
    static func create(at time: Date, title: String = "", in context: NSManagedObjectContext) -> Experience {
        let experience = Experience(context: context)
        experience.creationDate = Date()
        experience.sortDate = time
        experience.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? time.asDateString : title
        experience.text = ""
        return experience
    }

    public static func < (lhs: Experience, rhs: Experience) -> Bool {
        lhs.sortDateUnwrapped > rhs.sortDateUnwrapped
    }

    // Single passes instead of sorting, since these are read for every journal row on each render
    private var ingestionsUnsorted: [Ingestion] {
        ingestions?.allObjects as? [Ingestion] ?? []
    }

    // The journal is sorted and searched by the stored sortDate, so it follows the first ingestion's time whenever
    // a save moves, adds or removes ingestions. Experiences without ingestions keep theirs.
    static func updateSortDates(beforeSaving context: NSManagedObjectContext) {
        var experiences = Set<Experience>()
        for case let ingestion as Ingestion in context.insertedObjects.union(context.updatedObjects) {
            let changedKeys = ingestion.changedValues().keys
            guard ingestion.isInserted || changedKeys.contains("time") || changedKeys.contains("experience") else { continue }
            if let experience = ingestion.experience {
                experiences.insert(experience)
            }
            if let previousExperience = ingestion.committedValues(forKeys: ["experience"])["experience"] as? Experience {
                experiences.insert(previousExperience)
            }
        }
        for case let ingestion as Ingestion in context.deletedObjects {
            if let experience = ingestion.committedValues(forKeys: ["experience"])["experience"] as? Experience {
                experiences.insert(experience)
            }
        }
        for experience in experiences where !experience.isDeleted {
            let firstTime = experience.ingestionsUnsorted.filter { !$0.isDeleted }.compactMap(\.time).min()
            if let firstTime, experience.sortDate != firstTime {
                experience.sortDate = firstTime
            }
        }
    }

    var sortDateUnwrapped: Date {
        ingestionsUnsorted.compactMap(\.time).min() ?? sortDate ?? creationDateUnwrapped
    }

    var creationDateUnwrapped: Date {
        creationDate ?? Date()
    }

    var location: ExperienceLocation? {
        ingestionsUnsorted.min()?.location ?? legacyLocation
    }

    var titleUnwrapped: String {
        title ?? creationDateUnwrappedString
    }

    var textUnwrapped: String {
        text ?? ""
    }

    var creationDateUnwrappedString: String {
        creationDateUnwrapped.asDateString
    }

    var myIngestionsSorted: [Ingestion] {
        ExperienceLogic.myIngestions(from: ingestionsSorted)
    }

    var ingestionsSorted: [Ingestion] {
        (ingestions?.allObjects as? [Ingestion] ?? []).sorted()
    }

    var timedNotesSorted: [TimedNote] {
        (timedNotes?.allObjects as? [TimedNote] ?? []).sorted()
    }

    var consumerNames: [String] {
        otherIngestions.map(\.consumerNameUnwrapped).uniqued()
    }

    var ratingsUnwrapped: [ShulginRating] {
        ratings?.allObjects as? [ShulginRating] ?? []
    }

    var ratingsWithTimeSorted: [ShulginRating] {
        ratingsUnwrapped.filter { rating in
            rating.time != nil
        }.sorted()
    }

    var maxRating: ShulginRatingOption? {
        ratingsUnwrapped.map { rating in
            rating.optionUnwrapped
        }.max()
    }

    var overallRating: ShulginRating? {
        ratingsUnwrapped.first { rating in
            rating.time == nil
        }
    }

    var ingestionColors: [Color] {
        ingestionsSorted.map(\.substanceColor.swiftUIColor)
    }

    // As shown, so with the user's display names
    var distinctUsedSubstanceNames: [String] {
        ingestionsSorted.map { ing in
            ing.substanceDisplayName
        }.uniqued()
    }

    // An ingestion added to an experience whose last ingestion is over 20 hours ago starts at that time instead of now
    var startTimeForAddedIngestion: Date? {
        guard let lastTime = ingestionsUnsorted.compactMap(\.time).max(), lastTime.distance(to: .now) > 20 * 60 * 60 else {
            return nil
        }
        return lastTime
    }

    var isCurrent: Bool {
        let twelveHours: TimeInterval = 12 * 60 * 60
        let now = Date().timeIntervalSinceReferenceDate
        if let lastIngestionTime = ingestionsUnsorted.compactMap(\.time).max(),
           now - lastIngestionTime.timeIntervalSinceReferenceDate < twelveHours {
            return true
        }
        return now - sortDateUnwrapped.timeIntervalSinceReferenceDate < twelveHours
    }

    var timedNotesForTimeline: [EverythingForOneTimedNote] {
        timedNotesSorted.filter { $0.isPartOfTimeline }.map { timedNote in
            EverythingForOneTimedNote(
                time: timedNote.timeUnwrapped,
                color: timedNote.color
            )
        }
    }

    var otherIngestions: [Ingestion] {
        ExperienceLogic.otherIngestions(from: ingestionsSorted)
    }

    var interactions: [Interaction] {
        ExperienceLogic.interactions(from: ingestionsSorted)
    }

    var substancesUsed: [Substance] {
        ExperienceLogic.substancesUsed(from: ingestionsSorted)
    }

    func getMyTimeLineModel(
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool,
        combinesComparableRoutes: Bool = UserDefaults.standard.bool(forKey: TimelineModel.combinesComparableRoutesKey)
    ) -> TimelineModel {
        liveActivityState(
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            combinesComparableRoutes: combinesComparableRoutes
        ).timelineModel
    }

    // The user's own timeline, in the form sent to the live activity
    func liveActivityState(
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool,
        combinesComparableRoutes: Bool = UserDefaults.standard.bool(forKey: TimelineModel.combinesComparableRoutesKey)
    ) -> TimelineWidgetAttributes.ContentState {
        TimelineWidgetAttributes.ContentState(
            substanceGroups: getSubstanceIngestionGroups(ingestions: myIngestionsSorted),
            everythingForEachRating: ratingsWithTimeSorted
                .filter { !$0.isHiddenInTimeline }
                .map { EverythingForOneRating(time: $0.timeUnwrapped, option: $0.optionUnwrapped) },
            everythingForEachTimedNote: timedNotesForTimeline,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            combinesComparableRoutes: combinesComparableRoutes
        )
    }

    func getConsumers(
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) -> [ConsumerWithIngestions] {
        Dictionary(grouping: otherIngestions, by: \.consumerNameUnwrapped).map { consumerName, ingestions in
            ConsumerWithIngestions(
                consumerName: consumerName,
                ingestionsSorted: ingestions.sorted(),
                timelineModel: ExperienceLogic.timelineModel(
                    from: ingestions,
                    areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                )
            )
        }.sorted()
    }

    var chartData: ExperienceLogic.ChartData {
        ExperienceLogic.chartData(for: ingestionsSorted)
    }
}
