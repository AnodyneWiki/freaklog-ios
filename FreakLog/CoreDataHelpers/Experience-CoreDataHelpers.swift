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
        var colors = [Color]()
        for ingestion in ingestionsSorted {
            colors.append(ingestion.substanceColor.swiftUIColor)
        }
        return colors
    }

    var distinctUsedSubstanceNames: [String] {
        ingestionsSorted.map { ing in
            ing.substanceNameUnwrapped
        }.uniqued()
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
        hiddenIngestions: [ObjectIdentifier],
        hiddenRatings: [ObjectIdentifier],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) -> TimelineModel {
        liveActivityState(
            hiddenIngestions: hiddenIngestions,
            hiddenRatings: hiddenRatings,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        ).timelineModel
    }

    // The user's own timeline, in the form sent to the live activity
    func liveActivityState(
        hiddenIngestions: [ObjectIdentifier] = [],
        hiddenRatings: [ObjectIdentifier] = [],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) -> TimelineWidgetAttributes.ContentState {
        TimelineWidgetAttributes.ContentState(
            substanceGroups: getSubstanceIngestionGroups(ingestions: myIngestionsSorted.filter { !hiddenIngestions.contains($0.id) }),
            everythingForEachRating: ratingsWithTimeSorted
                .filter { !hiddenRatings.contains($0.id) }
                .map { EverythingForOneRating(time: $0.timeUnwrapped, option: $0.optionUnwrapped) },
            everythingForEachTimedNote: timedNotesForTimeline,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
    }

    func getConsumers(hiddenIngestions: [ObjectIdentifier], areRedosesDrawnIndividually: Bool, areSubstanceHeightsIndependent: Bool) -> [ConsumerWithIngestions] {
        Dictionary(grouping: otherIngestions, by: \.consumerNameUnwrapped).map { consumerName, ingestions in
            ConsumerWithIngestions(
                consumerName: consumerName,
                ingestionsSorted: ingestions.sorted(),
                timelineModel: ExperienceLogic.timelineModel(
                    from: ingestions.filter { !hiddenIngestions.contains($0.id) },
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
