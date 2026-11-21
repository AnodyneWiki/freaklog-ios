import ActivityKit
import CoreData
import Foundation

enum LiveActivities {
    // Live activities need iOS 16.2, don't run on Mac and can be turned off by the user.
    @MainActor static var areAvailable: Bool {
        guard #available(iOS 16.2, *) else { return false }
        return ActivityManager.shared.areActivitiesAvailable
    }
}

// Runs the live activity of one experience. Once started it follows that experience by itself:
// every change to the journal or the timeline settings redraws it, and deleting the experience ends it.
@available(iOS 16.2, *)
@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()
    lazy var authorizationInfo = ActivityAuthorizationInfo()
    @Published var isActivityActive = false
    private var activityStateTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    @Published private(set) var shownExperience: Experience?
    // What the experience screen hides; hidden ingestions and ratings are left out of the activity too
    private var hiddenIngestions: Set<ObjectIdentifier> = []
    private var hiddenRatings: Set<ObjectIdentifier> = []
    private var shownState: TimelineWidgetAttributes.ContentState?

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
            shownExperience = Self.experience(at: firstActivity.attributes.experienceURI)
            observeStateUpdates(of: firstActivity)
        }
        let context = PersistenceController.shared.viewContext
        observers = [
            NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: context,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            },
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            },
        ]
    }

    deinit {
        activityStateTask?.cancel()
        refreshTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func isShowing(_ experience: Experience) -> Bool {
        isActivityActive && shownExperience == experience
    }

    // Starts the activity for the experience, or switches the running activity over to it
    func show(
        _ experience: Experience,
        hiddenIngestions: Set<ObjectIdentifier> = [],
        hiddenRatings: Set<ObjectIdentifier> = []
    ) async {
        guard areActivitiesAvailable else { return }
        self.hiddenIngestions = hiddenIngestions
        self.hiddenRatings = hiddenRatings
        let state = state(for: experience)
        if isShowing(experience), let activity = Activity<TimelineWidgetAttributes>.activities.first {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await stop()
            startActivity(state, for: experience)
        }
        shownExperience = experience
        shownState = state
    }

    // Leaves what the experience screen hides out of the activity, if it shows that experience
    func setHidden(ingestions: Set<ObjectIdentifier>, ratings: Set<ObjectIdentifier>, in experience: Experience) {
        guard isShowing(experience) else { return }
        hiddenIngestions = ingestions
        hiddenRatings = ratings
        scheduleRefresh()
    }

    func stop() async {
        guard areActivitiesAvailable else { return }
        for activity in Activity<TimelineWidgetAttributes>.activities {
            let finalContent = shownState.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
        shownExperience = nil
        shownState = nil
    }

    private func startActivity(_ state: TimelineWidgetAttributes.ContentState, for experience: Experience) {
        let attributes = TimelineWidgetAttributes(
            name: "Passed from app",
            experienceURI: experience.objectID.isTemporaryID ? nil : experience.objectID.uriRepresentation()
        )
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            observeStateUpdates(of: newActivity)
        } catch {
            print("Failed to start activity: \(error.localizedDescription)")
        }
    }

    private func observeStateUpdates(of activity: Activity<TimelineWidgetAttributes>) {
        activityStateTask?.cancel()
        activityStateTask = Task { [weak self] in
            for await activityState in activity.activityStateUpdates {
                self?.isActivityActive = activityState == .active
            }
        }
    }

    // Changes come in bursts (a save touches several objects, typing edits a note), so they are coalesced
    private func scheduleRefresh() {
        guard isActivityActive, shownExperience != nil, refreshTask == nil else { return }
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refresh()
            refreshTask = nil
        }
    }

    private func refresh() async {
        guard isActivityActive, let experience = shownExperience else { return }
        guard !experience.isDeleted, experience.managedObjectContext != nil else {
            await stop()
            return
        }
        let state = state(for: experience)
        guard state != shownState, let activity = Activity<TimelineWidgetAttributes>.activities.first else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        shownState = state
    }

    private func state(for experience: Experience) -> TimelineWidgetAttributes.ContentState {
        let defaults = UserDefaults.standard
        return experience.liveActivityState(
            hiddenIngestions: hiddenIngestions,
            hiddenRatings: hiddenRatings,
            areRedosesDrawnIndividually: defaults.object(forKey: PersistenceController.areRedosesDrawnIndividuallyKey)
                as? Bool ?? true,
            areSubstanceHeightsIndependent: defaults.object(forKey: PersistenceController.independentSubstanceHeightKey)
                as? Bool ?? true
        )
    }

    private static func experience(at uri: URL?) -> Experience? {
        let context = PersistenceController.shared.viewContext
        guard
            let uri,
            let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)
        else { return nil }
        return try? context.existingObject(with: objectID) as? Experience
    }
}
