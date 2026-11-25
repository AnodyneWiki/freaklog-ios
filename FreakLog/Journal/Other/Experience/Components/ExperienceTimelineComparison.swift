import SwiftUI

struct ExperienceTimelineComparison: View {
    @ObservedObject var experience: Experience
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var drawsRedosesIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var usesIndependentHeights = true
    @AppStorage(TimelineModel.combinesComparableRoutesKey) private var combinesRoutes = false
    @Binding var selectedTime: Date?

    var body: some View {
        let participants = Dictionary(grouping: experience.ingestionsSorted) { $0.isMine ? "" : $0.consumerNameUnwrapped }
        let visibleParticipants = participants.mapValues { $0.filter { !$0.isHiddenFromTimeline && !$0.isUnconfirmed } }
        let models = visibleParticipants.values.filter { !$0.isEmpty }.map { model(for: $0) }
        let range = Self.sharedTimeRange(for: models)
        let cursor = selectedTime.flatMap { time in range?.contains(time) == true ? time : nil }
        List {
            if let range {
                Section {
                    LabeledContent("Time Range") {
                        Text((range.lowerBound..<range.upperBound).formatted(.interval.month(.abbreviated).day().hour().minute()))
                            .multilineTextAlignment(.trailing)
                    }
                    if let cursor {
                        LabeledContent("Cursor Time") {
                            Text(cursor, format: TimelineCursorEntry.dateFormat).monospacedDigit()
                        }
                    }
                } footer: {
                    Text("All charts share the same time axis. Heights are scaled within each person’s chart.")
                }
            }
            ForEach(visibleParticipants.keys.sorted(), id: \.self) { name in
                Section {
                    let ingestions = visibleParticipants[name] ?? []
                    if let range, !ingestions.isEmpty {
                        let timeline = model(for: ingestions, alignedTo: range)
                        EffectTimeline(
                            timelineModel: timeline,
                            height: 150,
                            timeDisplayStyle: .regular,
                            cursorTime: cursor,
                            onTimeSelected: { selectedTime = $0 }
                        )
                        if let cursor, let estimate = timeline.effectEstimate(at: cursor),
                           let phase = estimate.phase(at: cursor)?.phase {
                            LabeledContent("Estimated Phase", value: "\(estimate.substance) · \(phase.rawValue)")
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
        .toolbar {
            if models.contains(where: \.supportsCombiningRoutes) {
                Menu {
                    Toggle("Combine Comparable Routes", isOn: $combinesRoutes)
                } label: {
                    Label("Timeline Options", systemImage: "ellipsis.circle")
                }
            }
        }
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
