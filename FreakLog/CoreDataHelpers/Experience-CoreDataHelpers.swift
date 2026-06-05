import SwiftUI

extension Experience: Comparable {
    public static func < (lhs: Experience, rhs: Experience) -> Bool {
        lhs.sortDateUnwrapped > rhs.sortDateUnwrapped
    }

    var sortDateUnwrapped: Date {
        ingestionsSorted.first?.time ?? sortDate ?? creationDateUnwrapped
    }

    var creationDateUnwrapped: Date {
        creationDate ?? Date()
    }

    var location: ExperienceLocation? {
        ingestionsSorted.first?.location ?? legacyLocation
    }

    var titleUnwrapped: String {
        title ?? creationDateUnwrappedString
    }

    var textUnwrapped: String {
        text ?? ""
    }

    var creationDateUnwrappedString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM y"
        return formatter.string(from: creationDateUnwrapped)
    }

    var myIngestionsSorted: [Ingestion] {
        ingestionsSorted.filter { ing in
            if let consumerName = ing.consumerName {
                return consumerName.trimmingCharacters(in: .whitespaces).isEmpty
            } else {
                return true
            }
        }
    }

    var ingestionsSorted: [Ingestion] {
        (ingestions?.allObjects as? [Ingestion] ?? []).sorted()
    }

    var timedNotesSorted: [TimedNote] {
        (timedNotes?.allObjects as? [TimedNote] ?? []).sorted()
    }

    var consumerNames: [String] {
        ingestionsSorted.compactMap { ing in
            if let consumerName = ing.consumerName, !consumerName.trimmingCharacters(in: .whitespaces).isEmpty {
                return consumerName
            } else {
                return nil
            }
        }.uniqued()
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
        if let lastIngestionTime = ingestionsSorted.last?.time,
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
        let mine = Set(myIngestionsSorted)
        return ingestionsSorted.filter { !mine.contains($0) }
    }

    var myCumulativeDoses: [CumulativeDose] {
        let ingestionsBySubstance = Dictionary(grouping: myIngestionsSorted, by: { $0.substanceNameUnwrapped })
        return ingestionsBySubstance.compactMap { (substanceName: String, ingestions: [Ingestion]) in
            guard ingestions.count > 1 else { return nil }
            guard let color = ingestions.first?.substanceColor else { return nil }
            return CumulativeDose(ingestionsForSubstance: ingestions, substanceName: substanceName, substanceColor: color)
        }
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
        ExperienceLogic.timelineModel(
            from: myIngestionsSorted.filter { !hiddenIngestions.contains($0.id) },
            everythingForEachRating: ratingsWithTimeSorted
                .filter { !hiddenRatings.contains($0.id) }
                .map { EverythingForOneRating(time: $0.timeUnwrapped, option: $0.optionUnwrapped) },
            everythingForEachTimedNote: timedNotesForTimeline,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
    }

    func getConsumers(hiddenIngestions: [ObjectIdentifier], areRedosesDrawnIndividually: Bool, areSubstanceHeightsIndependent: Bool) -> [ConsumerWithIngestions] {
        let ingestionsByConsumer = Dictionary(grouping: otherIngestions, by: { $0.consumerName })
        var consumers = [ConsumerWithIngestions]()
        for (consumerName, ingestions) in ingestionsByConsumer {
            if let consumerName, !consumerName.trimmingCharacters(in: .whitespaces).isEmpty {
                let newConsumer = ConsumerWithIngestions(
                    consumerName: consumerName,
                    ingestionsSorted: ingestions.sorted(),
                    timelineModel: ExperienceLogic.timelineModel(
                        from: ingestions.filter { !hiddenIngestions.contains($0.id) },
                        areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                        areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                    )
                )
                consumers.append(newConsumer)
            }
        }
        return consumers.sorted()
    }

    var chartData: ExperienceLogic.ChartData {
        ExperienceLogic.chartData(for: ingestionsSorted)
    }
}
