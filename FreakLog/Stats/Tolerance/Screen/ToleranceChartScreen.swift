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
        toleranceWindows = ToleranceChartCalculator.getToleranceWindows(from: persisted + additionalSubstanceDays, substanceCompanions: Array(substanceCompanions))
        let substanceNamesInIngestions = Set(relevantIngestions.map { $0.substanceNameUnwrapped })
        let substanceNamesInToleranceWindows = Set(toleranceWindows.map { $0.substanceName })
        substancesInChart = SubstanceRepo.shared.getSubstances(names: substanceNamesInToleranceWindows).map { sub in
            sub.toSubstanceWithToleranceAndColor(substanceColor: substanceCompanions.first(where: { $0.substanceNameUnwrapped == sub.name })?.color ?? .red)
        }
        numberOfSubstancesInChart = substanceNamesInToleranceWindows.count
        let substancesWithoutToleranceWindows = substanceNamesInIngestions.subtracting(substanceNamesInToleranceWindows)
        substancesInIngestionsButNotChart = Array(substancesWithoutToleranceWindows)
    }
}
