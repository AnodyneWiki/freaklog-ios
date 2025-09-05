import ActivityKit
import Foundation

@available(iOS 16.2, *)
@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()
    let authorizationInfo = ActivityAuthorizationInfo()
    @Published var isActivityActive = false
    private var activityStateTask: Task<Void, Never>?

    init() {
        if let firstActivity = Activity<TimelineWidgetAttributes>.activities.first {
            isActivityActive = firstActivity.activityState == .active
            activityStateTask = Task { [weak self] in
                for await activityState in firstActivity.activityStateUpdates {
                    self?.isActivityActive = activityState == .active
                }
            }
        }
    }

    deinit {
        activityStateTask?.cancel()
    }

    func startOrUpdateActivity(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) async {
        if authorizationInfo.areActivitiesEnabled {
            if let firstActivity = Activity<TimelineWidgetAttributes>.activities.first, firstActivity.activityState == .active {
                await updateActivity(
                    activity: firstActivity,
                    substanceGroups: substanceGroups,
                    everythingForEachRating: everythingForEachRating,
                    everythingForEachTimedNote: everythingForEachTimedNote,
                    areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                )
            } else {
                await stopActivity(
                    substanceGroups: substanceGroups,
                    everythingForEachRating: everythingForEachRating,
                    everythingForEachTimedNote: everythingForEachTimedNote,
                    areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                )
                startActivity(
                    substanceGroups: substanceGroups,
                    everythingForEachRating: everythingForEachRating,
                    everythingForEachTimedNote: everythingForEachTimedNote,
                    areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                )
            }
        }
    }

    private func startActivity(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) {
        let attributes = TimelineWidgetAttributes(name: "Passed from app")
        let state = TimelineWidgetAttributes.ContentState(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activityStateTask = Task { [weak self] in
                for await activityState in newActivity.activityStateUpdates {
                    self?.isActivityActive = activityState == .active
                }
            }
        } catch {
            print("Failed to start activity: \(error.localizedDescription)")
        }
    }

    private func updateActivity(
        activity: Activity<TimelineWidgetAttributes>,
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) async {
        let state = TimelineWidgetAttributes.ContentState(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
        let updatedContent = ActivityContent(state: state, staleDate: nil)
        await activity.update(updatedContent)
    }

    func stopActivity(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool
    ) async {
        if authorizationInfo.areActivitiesEnabled {
            let state = TimelineWidgetAttributes.ContentState(
                substanceGroups: substanceGroups,
                everythingForEachRating: everythingForEachRating,
                everythingForEachTimedNote: everythingForEachTimedNote,
                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
            )
            let finalContent = ActivityContent(state: state, staleDate: nil)
            for activity in Activity<TimelineWidgetAttributes>.activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }
}
