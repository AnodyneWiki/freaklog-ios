import CoreData
import SwiftUI

struct ToleranceChartScreen: View {
    @State private var sinceDate = Date().addingTimeInterval(-3 * 30 * 24 * 60 * 60)
    @State private var toleranceWindows: [ToleranceWindow] = []
    @State private var substancesInIngestionsButNotChart: [String] = []
    @State private var numberOfSubstancesInChart = 0
    @State private var isPresentingSheet = false
    @State private var additionalSubstanceDays: [SubstanceAndDay] = []
    @State private var substancesInChart: [SubstanceWithToleranceAndColor] = []

    @FetchRequest(fetchRequest: PersistenceController.personalIngestionsRequest())
    var ingestions: FetchedResults<Ingestion>

    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    var body: some View {
        ToleranceChartScreenContent(toleranceWindows: toleranceWindows,
                                    sinceDate: $sinceDate,
                                    substancesInIngestionsButNotChart: substancesInIngestionsButNotChart,
                                    numberOfSubstancesInChart: numberOfSubstancesInChart,
                                    onAddTap: { isPresentingSheet.toggle() },
                                    substances: substancesInChart)
            .onAppear(perform: calculateScreen)
            .onChange(of: ingestions.count) { _ in
                calculateScreen()
            }
            .onChange(of: sinceDate) { _ in
                calculateScreen()
            }
            .sheet(isPresented: $isPresentingSheet) {
                AddToleranceIngestionScreen(finish: finishAddingIngestion)
            }
    }

    private func finishAddingIngestion(substanceAndDay: SubstanceAndDay) {
        additionalSubstanceDays.append(substanceAndDay)
        isPresentingSheet.toggle()
        calculateScreen()
    }

    private func calculateScreen() {
        let relevantIngestions = ingestions.prefix { ing in
            ing.timeUnwrapped > sinceDate
        }
        let persisted = relevantIngestions.map { ing in
            SubstanceAndDay(substanceName: ing.substanceNameUnwrapped, day: ing.timeUnwrapped)
        }
        let chartData = ExperienceLogic.chartData(for: persisted + additionalSubstanceDays, substanceCompanions: Array(substanceCompanions))
        toleranceWindows = chartData.toleranceWindows
        substancesInChart = chartData.substancesInChart
        numberOfSubstancesInChart = chartData.numberOfSubstancesInToleranceChart
        substancesInIngestionsButNotChart = chartData.namesOfSubstancesWithMissingTolerance
    }
}
