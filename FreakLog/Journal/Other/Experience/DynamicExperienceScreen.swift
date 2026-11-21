import SwiftUI

struct DynamicExperienceScreen: View {
    let ingestions: [Ingestion]

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var saveableTimeDisplayStyle: SaveableTimeDisplayStyle = .auto
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) var dynamicRange: DynamicRangeOption = .twentyFourHours

    var timeDisplayStyle: TimeDisplayStyle {
        saveableTimeDisplayStyle.resolved(isCurrent: ingestions.contains { dynamicRange.containsRecent($0.timeUnwrapped) })
    }

    var body: some View {
        let myIngestions = ExperienceLogic.myIngestions(from: ingestions)
        let timelineModel = ExperienceLogic.dynamicTimelineModel(
            from: myIngestions,
            range: dynamicRange,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )

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
                
                if isEyeOpen {
                    let cumulativeDoses = ExperienceLogic.myCumulativeDoses(from: myIngestions, includeSingleIngestions: true)
                    if !cumulativeDoses.isEmpty {
                        CumulativeDoseSection(
                            title: "Cumulative Dose over past \(dynamicRange.text)",
                            cumulativeDoses: cumulativeDoses.sorted { $0.firstIngestionTime < $1.firstIngestionTime },
                            isHidingDosageDots: isHidingDosageDots,
                            isEyeOpen: isEyeOpen
                        )
                    }
                }
            }

            if isEyeOpen && !isHidingToleranceChartInExperience {
                let chartData = ExperienceLogic.chartData(for: ingestions)
                if !chartData.toleranceWindows.isEmpty {
                    ToleranceChartSection(
                        chartData: chartData,
                        experienceStartDate: ingestions.first?.timeUnwrapped ?? Date(),
                        isTimeRelative: timeDisplayStyle == .relativeToNow
                    )
                }
            }

            if isEyeOpen && !isHidingSubstanceInfoInExperience {
                SubstanceInfoSections(
                    substancesUsed: ExperienceLogic.substancesUsed(from: ingestions),
                    interactions: ExperienceLogic.interactions(from: ingestions)
                )
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
