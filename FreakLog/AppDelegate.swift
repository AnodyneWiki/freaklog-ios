import UIKit
import CoreData
import Combine

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var isJournalReady = false
    private var cloudKitBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func application(_ app: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        setupCloudKitBackgroundTaskHandling()
        prepareJournal()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // When app enters background, start a background task for any pending CloudKit operations
        startCloudKitBackgroundTask()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // End the background task when app comes to foreground
        endCloudKitBackgroundTask()
        if isJournalReady {
            PhoneWatchSession.shared.retryPendingUndos()
            retryPendingRemoteDeletions()
        } else {
            prepareJournal()
        }
    }

    func prepareJournal() {
        guard !isJournalReady else { return }
        do {
            let persistence = PersistenceController.shared
            try persistence.loadData()
            try persistence.runPendingMigrations()
            if #available(iOS 16.2, *) {
                _ = ActivityManager.shared
            }
            isJournalReady = true
            PhoneWatchSession.shared.activate()
            retryPendingRemoteDeletions()
        } catch {
            print("Could not open journal: \(error)")
        }
    }

    private func retryPendingRemoteDeletions() {
        Task { @MainActor in
            async let webhooks = WebhookManager.shared.retryPendingDeletions()
            async let leaderboards: Void = LeaderboardSyncManager.shared.retryPendingDeletions()
            _ = await (webhooks, leaderboards)
        }
    }

    private func setupCloudKitBackgroundTaskHandling() {
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitActivity),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )

        // Also listen for CloudKit container events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitEvent),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
    }

    @objc private func handleCloudKitActivity(_ notification: Notification) {
        startCloudKitBackgroundTask()
    }

    @objc private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        switch event.type {
        case .export, .import:
            startCloudKitBackgroundTask()
        default:
            break
        }
    }

    private func startCloudKitBackgroundTask() {
        guard cloudKitBackgroundTaskID == .invalid else { return }

        cloudKitBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CloudKit Sync Operations") { [weak self] in
            // Background task is about to expire, end it
            self?.endCloudKitBackgroundTask()
        }

        // End the background task after a reasonable time to prevent indefinite tasks
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.endCloudKitBackgroundTask()
        }
    }

    private func endCloudKitBackgroundTask() {
        guard cloudKitBackgroundTaskID != .invalid else { return }

        UIApplication.shared.endBackgroundTask(cloudKitBackgroundTaskID)
        cloudKitBackgroundTaskID = .invalid
    }
}
