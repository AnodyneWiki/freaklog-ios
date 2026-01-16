import SwiftUI

struct ExperienceLogic {
    static func myIngestions(from ingestions: [Ingestion]) -> [Ingestion] {
        ingestions.filter { $0.consumerNameUnwrapped.isEmpty }
    }
    
    static func otherIngestions(from ingestions: [Ingestion]) -> [Ingestion] {
        ingestions.filter { !$0.consumerNameUnwrapped.isEmpty }
    }
    
    static func substancesUsed(from ingestions: [Ingestion]) -> [Substance] {
        ingestions
            .map { $0.substanceNameUnwrapped }
            .uniqued()
            .compactMap { SubstanceRepo.shared.getSubstance(name: $0) }
    }
    
    static func interactions(from ingestions: [Ingestion]) -> [Interaction] {
        let substanceNames = ingestions.filter({ $0.consumerName == nil }).map { $0.substanceNameUnwrapped }.uniqued()
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
    
    struct ChartData {
        let toleranceWindows: [ToleranceWindow]
        let substancesInChart: [SubstanceWithToleranceAndColor]
        let numberOfSubstancesInToleranceChart: Int
        let namesOfSubstancesWithMissingTolerance: [String]
    }
    
    static func chartData(for ingestions: [Ingestion]) -> ChartData {
        let lastIngestionDate = ingestions.last?.timeUnwrapped ?? Date.now
        let threeMonthsBefore = lastIngestionDate.addingTimeInterval(-3 * 30 * 24 * 60 * 60)
        let ingestionsForChart = PersistenceController.shared.getIngestionsBetween(startDate: threeMonthsBefore, endDate: lastIngestionDate).filter { ing in
            ing.consumerNameUnwrapped.isEmpty
        }
        let substanceDays = ingestionsForChart.map { ing in
            SubstanceAndDay(substanceName: ing.substanceNameUnwrapped, day: ing.timeUnwrapped)
        }
        let substanceCompanions = PersistenceController.shared.getSubstanceCompanions()
        let allWindowsInLast3Months = ToleranceChartCalculator.getToleranceWindows(
            from: substanceDays,
            substanceCompanions: Array(substanceCompanions)
        )
        let toleranceWindowsSorted = allWindowsInLast3Months.sorted { lhs, rhs in
            lhs.start < rhs.start
        }
        let namesOfSubstancesInChart = toleranceWindowsSorted.map { $0.substanceName }.uniqued()
        let substancesInChart = SubstanceRepo.shared.getSubstances(names: namesOfSubstancesInChart).map { sub in
            sub.toSubstanceWithToleranceAndColor(substanceColor: substanceCompanions.first(where: { $0.substanceNameUnwrapped == sub.name })?.color ?? .red)
        }
        let numberOfSubstancesInToleranceChart = namesOfSubstancesInChart.count
        let namesOfSubstancesInIngestions = Set(ingestionsForChart.map { $0.substanceNameUnwrapped })
        let namesOfSubstancesWithWindows = Set(allWindowsInLast3Months.map { $0.substanceName })
        let namesOfSubstancesWithoutWindows = namesOfSubstancesInIngestions.subtracting(namesOfSubstancesWithWindows)
        let namesOfSubstancesWithMissingTolerance = Array(namesOfSubstancesWithoutWindows)
        return ChartData(
            toleranceWindows: toleranceWindowsSorted,
            substancesInChart: substancesInChart,
            numberOfSubstancesInToleranceChart: numberOfSubstancesInToleranceChart,
            namesOfSubstancesWithMissingTolerance: namesOfSubstancesWithMissingTolerance
        )
    }
}
