import SwiftUI

struct DynamicExperienceScreen: View {
    let ingestions: [Ingestion]

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var timeDisplayStyleText: String = SaveableTimeDisplayStyle.auto.rawValue
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) var dynamicExperienceRangeHours: Int = 24

    var timeDisplayStyle: TimeDisplayStyle {
        let style = SaveableTimeDisplayStyle(rawValue: timeDisplayStyleText) ?? .regular
        switch style {
        case .regular: return .regular
        case .auto:
            // Auto logic: relative if any ingestion is recent (within dynamic range), otherwise regular
            // For a "Dynamic" screen, usually everything is recent, but we follow the rule.
            let window = TimeInterval(dynamicExperienceRangeHours) * 60 * 60
            if ingestions.contains(where: { $0.timeUnwrapped > Date.now.addingTimeInterval(-window) }) {
                return .relativeToNow
            } else {
                return .regular
            }
        case .relativeToNow: return .relativeToNow
        case .relativeToStart: return .relativeToStart
        case .between: return .between
        }
    }

    var body: some View {
        let myIngestions = ExperienceLogic.myIngestions(from: ingestions)
        var timelineModel: TimelineModel {
            let anchorTime = myIngestions.map(\.timeUnwrapped).max() ?? Date()
            let rangeSeconds = TimeInterval(dynamicExperienceRangeHours * 60 * 60)
            let startTime = anchorTime.addingTimeInterval(-rangeSeconds)
            let visibleRange = startTime...anchorTime

            return ExperienceLogic.timelineModel(
                from: myIngestions,
                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                visibleTimeRange: visibleRange
            )
        }
        
        List {
            if timelineModel.isWorthDrawing {
                Section {
                    EffectTimeline(
                        timelineModel: timelineModel,
                        height: 200,
                        timeDisplayStyle: timeDisplayStyle
                    )
                } header: {
                    HStack {
                        Text("Timeline")
                        Spacer()
                        NavigationLink(value: GlobalNavigationDestination.timeline(
                            timelineModel: timelineModel,
                            timeDisplayStyle: timeDisplayStyle)) {
                                Label("Timeline screen", systemImage: "arrow.down.left.and.arrow.up.right.square").labelStyle(.iconOnly)
                            }
                    }
                }
                
                let cumulativeDoses = ExperienceLogic.myCumulativeDoses(from: myIngestions, includeSingleIngestions: true)
                if !cumulativeDoses.isEmpty && isEyeOpen {
                    let rangeText = DynamicRangeOption(rawValue: dynamicExperienceRangeHours)?.text ?? "\(dynamicExperienceRangeHours)h"
                    Section("Cumulative Dose over past \(rangeText)") {
                        ForEach(cumulativeDoses.sorted(by: { $0.firstIngestionTime < $1.firstIngestionTime })) { cumulative in
                            if let substance = SubstanceRepo.shared.getSubstance(name: cumulative.substanceName) {
                                NavigationLink(value: GlobalNavigationDestination.dose(substance: substance)) {
                                    CumulativeDoseRow(
                                        substanceName: cumulative.substanceName,
                                        substanceColor: cumulative.substanceColor,
                                        cumulativeRoutes: cumulative.cumulativeRoutes,
                                        isHidingDosageDots: isHidingDosageDots,
                                        isEyeOpen: isEyeOpen
                                    )
                                }
                            } else {
                                CumulativeDoseRow(
                                    substanceName: cumulative.substanceName,
                                    substanceColor: cumulative.substanceColor,
                                    cumulativeRoutes: cumulative.cumulativeRoutes,
                                    isHidingDosageDots: isHidingDosageDots,
                                    isEyeOpen: isEyeOpen
                                )
                            }
                        }
                    }
                }
            }
            
            let cd = ExperienceLogic.chartData(for: ingestions)
            if !cd.toleranceWindows.isEmpty && !isHidingToleranceChartInExperience && isEyeOpen {
                Section {
                    ToleranceChart(
                        toleranceWindows: cd.toleranceWindows,
                        numberOfRows: cd.numberOfSubstancesInToleranceChart,
                        timeOption: .onlyIfCurrentTimeInChart,
                        experienceStartDate: (ingestions.first?.timeUnwrapped ?? Date()).getDateWithoutTime(),
                        isTimeRelative: timeDisplayStyle == .relativeToNow
                    )
                } header: {
                    HStack {
                        Text("Tolerance")
                        Spacer()
                        NavigationLink(value: GlobalNavigationDestination.toleranceTexts(substances: cd.substancesInChart)) {
                            Label("Tolerance info", systemImage: "doc.plaintext").labelStyle(.iconOnly)
                        }
                    }
                } footer: {
                    if !cd.namesOfSubstancesWithMissingTolerance.isEmpty {
                        Text("Excluding ") + Text(cd.namesOfSubstancesWithMissingTolerance, format: .list(type: .and))
                    }
                }
            }
            
            let substancesUsed = ExperienceLogic.substancesUsed(from: ingestions)
            let interactions = ExperienceLogic.interactions(from: ingestions)
            if !interactions.isEmpty && isEyeOpen && !isHidingSubstanceInfoInExperience {
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
            if isEyeOpen && !isHidingSubstanceInfoInExperience && !substancesUsed.isEmpty {
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
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Overview")
                    .font(.headline)
            }
        }
    }
}
