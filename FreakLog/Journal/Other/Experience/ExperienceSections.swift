import SwiftUI

// Sections shared by ExperienceScreen and DynamicExperienceScreen.

struct CumulativeDoseSection: View {
    let title: String
    let cumulativeDoses: [CumulativeDose]
    let isHidingDosageDots: Bool
    let isEyeOpen: Bool

    var body: some View {
        Section(title) {
            ForEach(cumulativeDoses) { cumulative in
                let row = CumulativeDoseRow(
                    substanceName: cumulative.substanceName,
                    substanceColor: cumulative.substanceColor,
                    cumulativeRoutes: cumulative.cumulativeRoutes,
                    isHidingDosageDots: isHidingDosageDots,
                    isEyeOpen: isEyeOpen
                )
                if let substance = SubstanceRepo.shared.getSubstance(name: cumulative.substanceName) {
                    NavigationLink(value: GlobalNavigationDestination.dose(substance: substance)) {
                        row
                    }
                } else {
                    row
                }
            }
        }
    }
}

struct ToleranceChartSection: View {
    let chartData: ExperienceLogic.ChartData
    let experienceStartDate: Date
    let isTimeRelative: Bool

    var body: some View {
        Section {
            ToleranceChart(
                toleranceWindows: chartData.toleranceWindows,
                numberOfRows: chartData.numberOfSubstancesInToleranceChart,
                timeOption: .onlyIfCurrentTimeInChart,
                experienceStartDate: experienceStartDate.getDateWithoutTime(),
                isTimeRelative: isTimeRelative
            )
        } header: {
            HStack {
                Text("Tolerance")
                Spacer()
                NavigationLink(value: GlobalNavigationDestination.toleranceTexts(substances: chartData.substancesInChart)) {
                    Label("Tolerance info", systemImage: "doc.plaintext").labelStyle(.iconOnly)
                }
            }
        } footer: {
            if !chartData.namesOfSubstancesWithMissingTolerance.isEmpty {
                Text("Excluding ") + Text(chartData.namesOfSubstancesWithMissingTolerance, format: .list(type: .and))
            }
        }
    }
}

// Interactions and Info sections. `infoFooter` is appended to the Info section.
struct SubstanceInfoSections<InfoFooter: View>: View {
    let substancesUsed: [Substance]
    let interactions: [Interaction]
    @ViewBuilder var infoFooter: () -> InfoFooter

    var body: some View {
        if !interactions.isEmpty {
            Section("Interactions") {
                ForEach(interactions) { interaction in
                    NavigationLink(value: GlobalNavigationDestination.allInteractions(substancesToCheck: substancesUsed)) {
                        InteractionPairRow(
                            aName: interaction.aName,
                            bName: interaction.bName,
                            interactionType: interaction.interactionType
                        )
                    }
                }
            }
        }
        if !substancesUsed.isEmpty {
            Section("Info") {
                ForEach(substancesUsed) { substance in
                    NavigationLink(value: GlobalNavigationDestination.substance(substance: substance)) {
                        Label(substance.name, systemImage: "info.circle")
                    }
                }
                if substancesUsed.contains(where: { $0.isHallucinogen }) {
                    NavigationLink(value: GlobalNavigationDestination.saferHallucinogen) {
                        Label("Safer Hallucinogens", systemImage: "cross")
                    }
                }
                if interactions.isEmpty {
                    NavigationLink(value: GlobalNavigationDestination.allInteractions(substancesToCheck: substancesUsed)) {
                        Label("See Interactions", systemImage: "exclamationmark.triangle")
                    }
                }
                infoFooter()
            }
        }
    }
}

extension SubstanceInfoSections where InfoFooter == EmptyView {
    init(substancesUsed: [Substance], interactions: [Interaction]) {
        self.init(substancesUsed: substancesUsed, interactions: interactions, infoFooter: { EmptyView() })
    }
}
