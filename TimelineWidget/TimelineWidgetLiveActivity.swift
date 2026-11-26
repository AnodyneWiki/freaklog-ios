import ActivityKit
import SwiftUI
import WidgetKit

struct TimelineWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimelineWidgetAttributes.self) { context in
            LockScreenTimeline(model: context.state.timelineModel)
                .widgetURL(continueJournalURL)
        } dynamicIsland: { context in
            let timelineModel = context.state.timelineModel
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineTimer(interval: timelineModel.activityInterval, countsDown: false)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineTimer(interval: timelineModel.activityInterval, countsDown: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityTimelineChart(model: timelineModel, height: 90)
                        .padding(.horizontal, 5)
                }
            } compactLeading: {
                TimelineTimer(interval: timelineModel.activityInterval, countsDown: false, compact: true)
            } compactTrailing: {
                TimelineTimer(interval: timelineModel.activityInterval, countsDown: true, compact: true)
            } minimal: {
                Image(systemName: "eye")
                    .accessibilityLabel("Journal Timeline")
            }
            .contentMargins(.bottom, 13, for: .expanded)
            .widgetURL(continueJournalURL)
        }
    }
}

private extension TimelineModel {
    var activityInterval: ClosedRange<Date> {
        startTime ... startTime.addingTimeInterval(max(1, totalWidth))
    }
}

private struct LockScreenTimeline: View {
    let model: TimelineModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let interval = model.activityInterval
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Estimated Timeline")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text((interval.lowerBound..<interval.upperBound).formatted(.interval.hour().minute()))
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(Text(interval))
            } else {
                GeometryReader { geometry in
                    ActivityTimelineChart(model: model, height: geometry.size.height)
                }
            }
            ProgressView(timerInterval: interval, countsDown: false)
                .progressViewStyle(.linear)
                .accessibilityLabel("Estimated Timeline Progress")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(height: 160)
    }
}

private struct ActivityTimelineChart: View {
    let model: TimelineModel
    let height: CGFloat

    var body: some View {
        ZStack {
            EffectTimeline(
                timelineModel: model,
                height: height,
                timeDisplayStyle: .regular,
                isShowingCurrentTime: false,
                spaceToLabels: 7
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated Timeline")
        .accessibilityValue(Text(model.activityInterval))
    }
}

private struct TimelineTimer: View {
    let interval: ClosedRange<Date>
    let countsDown: Bool
    var compact = false

    var body: some View {
        Group {
            if compact {
                ViewThatFits(in: .horizontal) {
                    value.fixedSize(horizontal: true, vertical: false)
                    Image(systemName: countsDown ? "hourglass" : "clock")
                }
            } else {
                VStack(alignment: countsDown ? .trailing : .leading, spacing: 2) {
                    Text(countsDown ? "Remaining" : "Elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    value
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(countsDown ? "Estimated Time Remaining" : "Elapsed Time"))
        .accessibilityValue(value)
    }

    private var value: Text {
        Text(timerInterval: interval, countsDown: countsDown)
            .monospacedDigit()
    }
}

struct TimelineWidgetLiveActivity_Previews: PreviewProvider {
    static let attributes = TimelineWidgetAttributes(name: "You")
    static let contentState = TimelineWidgetAttributes.ContentState(
        substanceGroups: EffectTimeline_Previews.substanceGroups,
        everythingForEachRating: EffectTimeline_Previews.everythingForEachRating,
        everythingForEachTimedNote: EffectTimeline_Previews.everythingForEachTimedNote,
        areRedosesDrawnIndividually: false,
        areSubstanceHeightsIndependent: false
    )

    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Island Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Island Expanded")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Minimal")
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
    }
}
