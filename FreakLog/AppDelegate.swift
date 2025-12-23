import UIKit
import CoreData

class AppDelegate: NSObject, UIApplicationDelegate {
    private var cloudKitBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func application(_ app: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        PersistenceController.shared.loadData(app)
        setupCloudKitBackgroundTaskHandling()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // When app enters background, start a background task for any pending CloudKit operations
        startCloudKitBackgroundTask()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // End the background task when app comes to foreground
        endCloudKitBackgroundTask()
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
