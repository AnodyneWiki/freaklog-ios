import SwiftUI

struct ExperienceLogic {
    static func myIngestions(from ingestions: [Ingestion]) -> [Ingestion] {
        ingestions.filter(\.isMine)
    }
    
    static func otherIngestions(from ingestions: [Ingestion]) -> [Ingestion] {
        ingestions.filter { !$0.isMine }
    }
    
    static func substancesUsed(from ingestions: [Ingestion]) -> [Substance] {
        ingestions
            .map { $0.substanceNameUnwrapped }
            .uniqued()
            .compactMap { SubstanceRepo.shared.getSubstance(name: $0) }
    }
    
    static func interactions(from ingestions: [Ingestion]) -> [Interaction] {
        let substanceNames = myIngestions(from: ingestions).map(\.substanceNameUnwrapped).uniqued()
        var interactions: [Interaction] = []
        for subIndex in 0 ..< substanceNames.count {
            let name = substanceNames[subIndex]
            let otherNames = substanceNames.dropFirst(subIndex + 1)
            for otherName in otherNames {
                if let newInteraction = InteractionChecker.getInteractionBetween(aName: name, bName: otherName) {
                    interactions.append(newInteraction)
                }
            }
        }
        return interactions.sorted(by: { interaction1, interaction2 in
            interaction1.interactionType.dangerCount > interaction2.interactionType.dangerCount
        })
    }
    
    static func myCumulativeDoses(from ingestions: [Ingestion], includeSingleIngestions: Bool = false) -> [CumulativeDose] {
        let myIngs = myIngestions(from: ingestions)
        let ingestionsBySubstance = Dictionary(grouping: myIngs, by: { $0.substanceNameUnwrapped })
        return ingestionsBySubstance.compactMap { (substanceName: String, ingestions: [Ingestion]) in
            if !includeSingleIngestions {
                guard ingestions.count > 1 else { return nil }
            }
            guard let color = ingestions.first?.substanceColor else { return nil }
            return CumulativeDose(ingestionsForSubstance: ingestions, substanceName: substanceName, substanceColor: color)
        }
    }
    
    static func timelineModel(
        from ingestions: [Ingestion],
        everythingForEachRating: [EverythingForOneRating] = [],
        everythingForEachTimedNote: [EverythingForOneTimedNote] = [],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool,
        visibleTimeRange: ClosedRange<Date>? = nil
    ) -> TimelineModel {
        TimelineModel(
            substanceGroups: getSubstanceIngestionGroups(ingestions: ingestions),
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            visibleTimeRange: visibleTimeRange
        )
    }
    
    // Timeline showing the given range up to the latest of the ingestions
    static func dynamicTimelineModel(
        from ingestions: [Ingestion],
        range: DynamicRangeOption,
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) -> TimelineModel {
        let anchorTime = ingestions.map(\.timeUnwrapped).max() ?? Date()
        return timelineModel(
            from: ingestions,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            visibleTimeRange: anchorTime.addingTimeInterval(-range.duration) ... anchorTime
        )
    }

    struct ChartData {
        let toleranceWindows: [ToleranceWindow]
        let substancesInChart: [SubstanceWithToleranceAndColor]
        let numberOfSubstancesInToleranceChart: Int
        let namesOfSubstancesWithMissingTolerance: [String]
    }
    
    // Tolerance chart for the three months before the last of the given ingestions
    static func chartData(for ingestions: [Ingestion]) -> ChartData {
        let lastIngestionDate = ingestions.last?.timeUnwrapped ?? Date.now
        let threeMonthsBefore = lastIngestionDate.addingTimeInterval(-3 * 30 * 24 * 60 * 60)
        let ingestionsForChart = myIngestions(
            from: PersistenceController.shared.getIngestionsBetween(startDate: threeMonthsBefore, endDate: lastIngestionDate)
        )
        return chartData(
            for: ingestionsForChart.map { SubstanceAndDay(substanceName: $0.substanceNameUnwrapped, day: $0.timeUnwrapped) },
            substanceCompanions: PersistenceController.shared.getSubstanceCompanions()
        )
    }

    static func chartData(for substanceDays: [SubstanceAndDay], substanceCompanions: [SubstanceCompanion]) -> ChartData {
        let toleranceWindows = ToleranceChartCalculator.getToleranceWindows(
            from: substanceDays,
            substanceCompanions: substanceCompanions
        ).sorted { $0.start < $1.start }
        let namesOfSubstancesInChart = toleranceWindows.map(\.substanceName).uniqued()
        let colors = Dictionary(substanceCompanions.map { ($0.substanceNameUnwrapped, $0.color) }, uniquingKeysWith: { first, _ in first })
        let substancesInChart = SubstanceRepo.shared.getSubstances(names: namesOfSubstancesInChart).map { sub in
            sub.toSubstanceWithToleranceAndColor(substanceColor: colors[sub.name] ?? .fallback)
        }
        let namesWithoutWindows = Set(substanceDays.map(\.substanceName)).subtracting(namesOfSubstancesInChart)
        return ChartData(
            toleranceWindows: toleranceWindows,
            substancesInChart: substancesInChart,
            numberOfSubstancesInToleranceChart: namesOfSubstancesInChart.count,
            namesOfSubstancesWithMissingTolerance: Array(namesWithoutWindows)
        )
    }
}
