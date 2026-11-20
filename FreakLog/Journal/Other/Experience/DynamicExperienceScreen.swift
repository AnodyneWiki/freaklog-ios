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
        let anchorTime = myIngestions.map(\.timeUnwrapped).max() ?? Date()
        let rangeSeconds = TimeInterval(dynamicExperienceRangeHours * 60 * 60)
        let timelineModel = ExperienceLogic.timelineModel(
            from: myIngestions,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            visibleTimeRange: anchorTime.addingTimeInterval(-rangeSeconds)...anchorTime
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
                        let rangeText = DynamicRangeOption(rawValue: dynamicExperienceRangeHours)?.text ?? "\(dynamicExperienceRangeHours)h"
                        CumulativeDoseSection(
                            title: "Cumulative Dose over past \(rangeText)",
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
