import SwiftUI

struct ToleranceChartScreenContent: View {
    let toleranceWindows: [ToleranceWindow]
    @Binding var sinceDate: Date
    let substancesInIngestionsButNotChart: [String]
    let numberOfSubstancesInChart: Int
    let onAddTap: () -> Void
    let substances: [SubstanceWithToleranceAndColor]
    var confirmedDays: [SubstanceAndDay] = []

    @State private var isTimeRelative = false

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Start Date",
                    selection: $sinceDate,
                    displayedComponents: [.date]
                )
                Toggle("Relative time", isOn: $isTimeRelative).tint(.accentColor)
                ToleranceChart(
                    toleranceWindows: toleranceWindows,
                    numberOfRows: numberOfSubstancesInChart,
                    timeOption: .alwaysShow,
                    experienceStartDate: nil,
                    isTimeRelative: isTimeRelative
                )
            } footer: {
                if !substancesInIngestionsButNotChart.isEmpty {
                    MissingToleranceText(substanceNames: substancesInIngestionsButNotChart)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .listRowSeparator(.hidden)
            Section {
                NavigationLink(value: GlobalNavigationDestination.toleranceChartExplanation) {
                    Label("Chart Limitations", systemImage: "info.circle")
                }
                if !substances.isEmpty {
                    NavigationLink(value: GlobalNavigationDestination.toleranceTexts(substances: substances)) {
                        Label("Tolerance Info", systemImage: "doc.plaintext")
                    }
                }
                NavigationLink {
                    CrossToleranceEvidenceScreen(confirmedDays: confirmedDays)
                } label: {
                    Label("Cross-Tolerance Evidence", systemImage: "link")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onAddTap) {
                    Label("Add Temporary Ingestion", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Tolerance")
    }
}

#Preview {
    NavigationStack {
        ToleranceChartScreenContent(
            toleranceWindows: ToleranceChartPreviewDataProvider.mock1,
            sinceDate: .constant(Date()),
            substancesInIngestionsButNotChart: ["2C-B", "DMT"],
            numberOfSubstancesInChart: 2,
            onAddTap: {},
            substances: []
        )
    }
}

#Preview {
    NavigationStack {
        ToleranceChartScreenContent(
            toleranceWindows: [],
            sinceDate: .constant(Date()),
            substancesInIngestionsButNotChart: [],
            numberOfSubstancesInChart: 0,
            onAddTap: {},
            substances: []
        )
    }
}
