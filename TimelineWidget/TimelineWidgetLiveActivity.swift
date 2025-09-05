import ActivityKit
import SwiftUI
import WidgetKit

struct TimelineWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimelineWidgetAttributes.self) { context in
            let timelineModel = TimelineModel(
                substanceGroups: context.state.substanceGroups,
                everythingForEachRating: context.state.everythingForEachRating,
                everythingForEachTimedNote: context.state.everythingForEachTimedNote,
                areRedosesDrawnIndividually: context.state.areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: context.state.areSubstanceHeightsIndependent
            )
            VStack(spacing: 0) {
                GeometryReader { geo in
                    EffectTimeline(
                        timelineModel: timelineModel,
                        height: geo.size.height,
                        timeDisplayStyle: .regular, 
                        isShowingCurrentTime: false,
                        spaceToLabels: 7
                    )
                }
                .padding(.bottom, 3)
                ProgressView(
                    timerInterval: timelineModel.startTime ... timelineModel.startTime.addingTimeInterval(timelineModel.totalWidth),
                    countsDown: false
                )
                .progressViewStyle(.linear)
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.horizontal, 10)
            .widgetURL(URL(string: openLatestExperience))
            .frame(height: 160) // in the documentation: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities it says that truncation only happens if the height exceeds 160 points
        } dynamicIsland: { context in
            let timelineModel = TimelineModel(
                substanceGroups: context.state.substanceGroups,
                everythingForEachRating: context.state.everythingForEachRating,
                everythingForEachTimedNote: context.state.everythingForEachTimedNote,
                areRedosesDrawnIndividually: context.state.areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: context.state.areSubstanceHeightsIndependent
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(timelineModel.startTime, style: .timer)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Date(timeInterval: timelineModel.totalWidth, since: timelineModel.startTime), style: .timer)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EffectTimeline(
                        timelineModel: timelineModel,
                        height: 90,
                        timeDisplayStyle: .regular, 
                        isShowingCurrentTime: false,
                        spaceToLabels: 7
                    )
                    .padding(.horizontal, 5)
                }
            } compactLeading: {
                Text(timelineModel.startTime, style: .timer)
            } compactTrailing: {
                Text(Date(timeInterval: timelineModel.totalWidth, since: timelineModel.startTime), style: .timer)
            } minimal: {
                Image(systemName: "eye")
            }
            .contentMargins(.bottom, 13, for: .expanded)
            .widgetURL(URL(string: openLatestExperience))
        }
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
