import ActivityKit
import Foundation

enum LiveActivities {
    // Live activities need iOS 16.2, don't run on Mac and can be turned off by the user.
    @MainActor static var areAvailable: Bool {
        guard #available(iOS 16.2, *) else { return false }
        return ActivityManager.shared.areActivitiesAvailable
    }
}

@available(iOS 16.2, *)
@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()
    lazy var authorizationInfo = ActivityAuthorizationInfo()
    @Published var isActivityActive = false
    private var activityStateTask: Task<Void, Never>?

    private var areActivitiesSupported: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac
    }

    var areActivitiesAvailable: Bool {
        areActivitiesSupported && authorizationInfo.areActivitiesEnabled
    }

    init() {
        guard areActivitiesSupported else { return }
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

    func startOrUpdateActivity(_ state: TimelineWidgetAttributes.ContentState) async {
        guard areActivitiesAvailable else { return }
        if let firstActivity = Activity<TimelineWidgetAttributes>.activities.first, firstActivity.activityState == .active {
            await firstActivity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await stopActivity(state)
            startActivity(state)
        }
    }

    private func startActivity(_ state: TimelineWidgetAttributes.ContentState) {
        let attributes = TimelineWidgetAttributes(name: "Passed from app")
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
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

    func stopActivity(_ state: TimelineWidgetAttributes.ContentState) async {
        guard areActivitiesAvailable else { return }
        let finalContent = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<TimelineWidgetAttributes>.activities {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }
}
