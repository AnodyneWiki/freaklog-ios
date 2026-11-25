import CoreData
import SwiftUI

struct ToleranceChartScreen: View {
    @State private var sinceDate = Date().addingTimeInterval(-3 * 30 * 24 * 60 * 60)
    @State private var isPresentingSheet = false
    @State private var additionalSubstanceDays: [SubstanceAndDay] = []

    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    var body: some View {
        StatsJournal { entries, _ in
            let persisted = entries.compactMap { entry -> SubstanceAndDay? in
                guard entry.isMine, !entry.isUnconfirmed, let time = entry.time, time > sinceDate else { return nil }
                return SubstanceAndDay(substanceName: entry.substanceNameUnwrapped, day: time)
            }
            let chart = ExperienceLogic.chartData(
                for: persisted + additionalSubstanceDays,
                substanceCompanions: Array(substanceCompanions)
            )

            ToleranceChartScreenContent(
                toleranceWindows: chart.toleranceWindows,
                sinceDate: $sinceDate,
                substancesInIngestionsButNotChart: chart.namesOfSubstancesWithMissingTolerance,
                numberOfSubstancesInChart: chart.numberOfSubstancesInToleranceChart,
                onAddTap: { isPresentingSheet.toggle() },
                substances: chart.substancesInChart,
                confirmedDays: persisted.filter { $0.day <= Date.now }
            )
        }
        .sheet(isPresented: $isPresentingSheet) {
            AddToleranceIngestionScreen { substanceAndDay in
                additionalSubstanceDays.append(substanceAndDay)
                isPresentingSheet = false
            }
        }
    }
}
