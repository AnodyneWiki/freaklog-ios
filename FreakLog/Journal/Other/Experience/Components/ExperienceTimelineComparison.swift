import SwiftUI

struct ExperienceTimelineComparison: View {
    @ObservedObject var experience: Experience
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var drawsRedosesIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var usesIndependentHeights = true

    var body: some View {
        let participants = Dictionary(grouping: experience.ingestionsSorted) { $0.isMine ? "" : $0.consumerNameUnwrapped }
        let visibleParticipants = participants.mapValues { $0.filter { !$0.isHiddenFromTimeline } }
        let models = visibleParticipants.values.filter { !$0.isEmpty }.map { model(for: $0) }
        let range = Self.sharedTimeRange(for: models)
        List {
            ForEach(participants.keys.sorted(), id: \.self) { name in
                Section {
                    let ingestions = visibleParticipants[name] ?? []
                    if let range, !ingestions.isEmpty {
                        let timeline = model(for: ingestions, alignedTo: range)
                        if timeline.isWorthDrawing {
                            EffectTimeline(timelineModel: timeline, height: 150, timeDisplayStyle: .regular)
                        } else {
                            Text("No effect timeline available").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No visible ingestions").foregroundStyle(.secondary)
                    }
                } header: {
                    if name.isEmpty {
                        Text("You")
                    } else {
                        Text(name)
                    }
                }
            }
        }
        .navigationTitle("Compare Timelines")
        .observeExperienceTimeline(experience)
    }

    private func model(for ingestions: [Ingestion], alignedTo range: ClosedRange<Date>? = nil) -> TimelineModel {
        ExperienceLogic.timelineModel(
            from: ingestions,
            areRedosesDrawnIndividually: drawsRedosesIndividually,
            areSubstanceHeightsIndependent: usesIndependentHeights,
            alignedTimeRange: range
        )
    }

    private static func sharedTimeRange(for models: [TimelineModel]) -> ClosedRange<Date>? {
        guard let start = models.map(\.startTime).min(),
              let end = models.map({ $0.startTime.addingTimeInterval($0.totalWidth) }).max(),
              start < end else { return nil }
        return start...end
    }
}
