@preconcurrency import CoreData //FIXME
import CloudKit
import Combine
import SwiftUI

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    static let preview: PersistenceController = .init(inMemory: true)

    let container: NSPersistentContainer

    private var isInitialized = false

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Published sync status for UI observation
    @Published var syncStatus: ICloudSyncStatus = .disabled

    /// Last sync timestamp
    @Published var lastSyncDate: Date?

    /// Token for tracking persistent history
    private var lastHistoryToken: NSPersistentHistoryToken?
    private let historyTokenKey = "PersistentHistoryToken"

    /// Background context for sync operations
    private lazy var backgroundContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }()

    static let needsToSeeWelcomeKey = "needsToSeeWelcome"
    static let isEyeOpenKey1 = "isEyeOpen"
    static let isEyeOpenKey2 = "isEyeOpen2"
    static let timeDisplayStyleKey = "timeDisplayStyle"
    static let timeDisplayStyleDurationSectionKey = "timeDisplayStyleDurationSection"
    static let isHidingDosageDotsKey = "isHidingDosageDots"
    static let isHidingToleranceChartInExperienceKey = "isHidingToleranceChartInExperience"
    static let isHidingSubstanceInfoInExperienceKey = "isHidingSubstanceInfoInExperience"
    static let areRedosesDrawnIndividuallyKey = "areRedosesDrawnIndividually"
    static let shouldAutomaticallyStartLiveActivityKey = "shouldAutomaticallyStartLiveActivity"
    static let independentSubstanceHeightKey = "independentSubstanceHeight"
    static let lastIngestionTimeOfExperienceWhereAddIngestionTappedKey = "lastIngestionTimeOfExperienceWhereAddIngestionTapped"
    static let clonedIngestionTimeKey = "clonedIngestionTimeKey"
    static let fabButtonPositionKey = "fabButtonPosition"
    static let isICloudSyncEnabledKey = "isICloudSyncEnabled"

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private static let modelName = "Main"

    private static let cloudKitContainerIdentifier = "iCloud.woof.freaklog"

    init(inMemory: Bool = false) {
        // Load saved history token
        if let tokenData = UserDefaults.standard.data(forKey: historyTokenKey),
           let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: tokenData) {
            lastHistoryToken = token
        }

        container = NSPersistentContainer(name: PersistenceController.modelName)
        let description = container.persistentStoreDescriptions.first

#if APP_WIDGET
        description?.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
#endif

        if !inMemory {
            // ALWAYS enable persistent history tracking - this is required for CloudKit
            // and must be consistent to avoid read-only mode issues when switching
            description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Check if iCloud sync is enabled
            let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)

            if isICloudSyncEnabled {
                // Enable CloudKit sync
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceController.cloudKitContainerIdentifier)
                description?.cloudKitContainerOptions = options
                syncStatus = .synced
            } else {
                // Local storage - no CloudKit options, but history tracking is still enabled
                description?.cloudKitContainerOptions = nil
                syncStatus = .disabled
            }
        }

        if inMemory {
            loadInMemoryStores(description: description)
            isInitialized = true
        } else {
            // Set up conflict resolution and remote change handling
            setupConflictResolution()
            setupRealtimeSync()
        }
    }

    /// Sets up real-time sync capabilities
    private func setupRealtimeSync() {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else { return }

        // Monitor for app becoming active to trigger sync
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.performFullSync()
            }
            .store(in: &cancellables)

        // Monitor for app entering background to save pending changes
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.saveBeforeBackground()
            }
            .store(in: &cancellables)

        // Periodic sync check every 30 seconds when app is active
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForRemoteChanges()
            }
            .store(in: &cancellables)

        print("☁️ Real-time sync configured")
    }

    /// Performs a full sync operation
    func performFullSync() {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else { return }

        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }

        // Process any pending history
        processRemoteChanges()

        // Refresh all objects
        viewContext.perform { [weak self] in
            self?.viewContext.refreshAllObjects()

            DispatchQueue.main.async {
                self?.syncStatus = .synced
                self?.lastSyncDate = Date()
                print("☁️ Full sync completed at \(Date())")
            }
        }
    }

    /// Checks for remote changes without full refresh
    private func checkForRemoteChanges() {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else { return }

        processRemoteChanges()
    }

    /// Processes remote changes from persistent history
    private func processRemoteChanges() {
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }

            let fetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastHistoryToken)

            guard let historyResult = try? self.backgroundContext.execute(fetchRequest) as? NSPersistentHistoryResult,
                  let history = historyResult.result as? [NSPersistentHistoryTransaction],
                  !history.isEmpty else {
                return
            }

            // Merge changes into view context
            let relevantChanges = history.compactMap { $0.objectIDNotification() }
            
            DispatchQueue.main.async {
                relevantChanges.forEach { notification in
                    self.viewContext.mergeChanges(fromContextDidSave: notification)
                }
            }

            // Update the history token
            if let lastToken = history.last?.token {
                self.lastHistoryToken = lastToken
                self.saveHistoryToken(lastToken)
            }

            print("☁️ Processed \(history.count) remote change(s)")
        }
    }

    /// Saves the history token to UserDefaults
    private func saveHistoryToken(_ token: NSPersistentHistoryToken) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: historyTokenKey)
        }
    }

    /// Saves pending changes before app goes to background
    private func saveBeforeBackground() {
        guard viewContext.hasChanges else { return }

        do {
            try viewContext.save()
            triggerCloudKitSync()
            print("☁️ Saved changes before background")
        } catch {
            print("⚠️ Failed to save before background: \(error)")
        }
    }

    /// Sets up conflict resolution policy and remote change notifications
    private func setupConflictResolution() {
        // Set merge policy: local changes win on a per-property basis
        // This means if the same property is modified on two devices,
        // the local (in-memory) change takes precedence
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Automatically merge changes from parent context (including CloudKit changes)
        viewContext.automaticallyMergesChangesFromParent = true

        // Listen for remote change notifications from CloudKit
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRemoteChange(notification)
            }
            .store(in: &cancellables)

        // Listen for context save notifications to handle conflicts
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleContextDidSave(notification)
            }
            .store(in: &cancellables)

        print("☁️ iCloud conflict resolution configured")
    }

    /// Handles remote changes from CloudKit
    private func handleRemoteChange(_ notification: Notification) {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else { return }

        // Fetch and merge changes from the persistent store history
        viewContext.perform { [weak self] in
            guard let self = self else { return }

            // Refresh all objects to incorporate remote changes
            self.viewContext.refreshAllObjects()

            print("☁️ Remote changes received and merged")
        }
    }

    /// Handles context save notifications for conflict detection
    private func handleContextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext,
              context != viewContext else { return }

        // Merge changes from other contexts (including CloudKit background context)
        viewContext.perform { [weak self] in
            self?.viewContext.mergeChanges(fromContextDidSave: notification)
        }
    }

    /// Enables or disables iCloud sync without requiring app restart
    /// This works by reconfiguring the persistent store with or without CloudKit options
    func setICloudSyncEnabled(_ enabled: Bool) {
        // Save the preference
        UserDefaults.standard.set(enabled, forKey: PersistenceController.isICloudSyncEnabledKey)

        // Save any pending changes
        if viewContext.hasChanges {
            try? viewContext.save()
        }

        // Get the current store
        guard let store = container.persistentStoreCoordinator.persistentStores.first,
              let storeURL = store.url else {
            print("Failed to get current store for iCloud sync switch")
            return
        }

        // Remove the current store
        do {
            try container.persistentStoreCoordinator.remove(store)
        } catch {
            print("Failed to remove store: \(error)")
            return
        }

        // Create new store description with updated options
        let newDescription = NSPersistentStoreDescription(url: storeURL)
        newDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        newDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if enabled {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceController.cloudKitContainerIdentifier)
            newDescription.cloudKitContainerOptions = options
        } else {
            newDescription.cloudKitContainerOptions = nil
        }

        // Add the store back with new configuration
        container.persistentStoreCoordinator.addPersistentStore(with: newDescription) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Failed to add store with new configuration: \(error)")
            } else {
                print("Successfully switched iCloud sync to: \(enabled)")
                // Re-apply merge policy after store switch
                self.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.viewContext.automaticallyMergesChangesFromParent = true
                
                // Reset context AFTER store is loaded to ensure consistency
                self.viewContext.reset()
            }
        }
    }

    // Tries to load data from persistent store, if it's available
    public func loadData(_ app: UIApplication) {
        tryLoadPersistentStores(app)
    }

    // Loads data from the in-memory store (only used for development)
    private func loadInMemoryStores(description: NSPersistentStoreDescription?) {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]


        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory Core Data stack: \(error)")
            }
        }

        viewContext.automaticallyMergesChangesFromParent = true
    }

    // Tries to load data from the persistent store, if it's available.
    // Specially handles the case of the app being prewarmed before first unlock, to supress erroneous app crashes.
    // There is likely a better way to fix it, but neither I nor the internet seems to know it.
    private func tryLoadPersistentStores(_ app: UIApplication) {
        if isInitialized { return }

        container.loadPersistentStores { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
                if (nsError.domain == "NSCocoaErrorDomain" && nsError.code == 256 && nsError.userInfo["NSSQLiteErrorDomain"] as? Int == 23) {
                    NSLog("Can't load core data stack due to BFU state")
                    NSLog("Cannot continue.")
                    // We want to end execution (since we can't continue) but not crash (to prevent the crash dialog)
                    exit(0)
                }
                else {
                    fatalError("Failed to load Core Data stack: \(error)")
                }
            }
            
            // Set up merge policy for conflict resolution AFTER stores are loaded
            self.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            self.viewContext.automaticallyMergesChangesFromParent = true
            self.isInitialized = true
        }
    }

    func deleteEverything() throws {
        let experienceDeleteRequest = Experience.fetchRequest()
        experienceDeleteRequest.includesPropertyValues = false
        let experiences = try viewContext.fetch(experienceDeleteRequest)
        for exp in experiences {
            viewContext.delete(exp)
        }
        let ingestionDeleteRequest = Ingestion.fetchRequest()
        ingestionDeleteRequest.includesPropertyValues = false
        let ingestions = try viewContext.fetch(ingestionDeleteRequest)
        for ing in ingestions {
            viewContext.delete(ing)
        }
        let customDeleteRequest = CustomSubstance.fetchRequest()
        customDeleteRequest.includesPropertyValues = false
        let customs = try viewContext.fetch(customDeleteRequest)
        for cust in customs {
            viewContext.delete(cust)
        }
        let companionDeleteRequest = SubstanceCompanion.fetchRequest()
        companionDeleteRequest.includesPropertyValues = false
        let companions = try viewContext.fetch(companionDeleteRequest)
        for com in companions {
            viewContext.delete(com)
        }
        let unitDeleteRequest = CustomUnit.fetchRequest()
        unitDeleteRequest.includesPropertyValues = false
        let customUnits = try viewContext.fetch(unitDeleteRequest)
        for unit in customUnits {
            viewContext.delete(unit)
        }
        let sprayDeleteRequest = Spray.fetchRequest()
        sprayDeleteRequest.includesPropertyValues = false
        let sprays = try viewContext.fetch(sprayDeleteRequest)
        for spray in sprays {
            viewContext.delete(spray)
        }
        try viewContext.save()
    }

    func migrateCompanionsAndExperienceSortDates() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            var companionsDict: [String: SubstanceCompanion] = [:]
            for ingestion in allIngestions {
                guard let name = ingestion.substanceName else { continue }
                guard let colorUnwrap = ingestion.color else { continue }
                if let companion = companionsDict[name] {
                    ingestion.substanceCompanion = companion
                } else {
                    let companion = SubstanceCompanion(context: viewContext)
                    companion.substanceName = name
                    companion.colorAsText = colorUnwrap
                    ingestion.substanceCompanion = companion
                    companionsDict[name] = companion
                }
            }
            let experienceFetchRequest = Experience.fetchRequest()
            let allExperiences = (try? viewContext.fetch(experienceFetchRequest)) ?? []
            for experience in allExperiences {
                experience.sortDate = experience.ingestionsSorted.first?.time ?? experience.creationDate
            }
            try? viewContext.save()
        }
    }

    func migrateIngestionNamesAndUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Psilocybin Mushrooms" {
                    ingestion.substanceName = "Psilocybin mushrooms"
                }
                if ingestion.units == "mg (THC)" {
                    ingestion.units = "mg"
                }
                if ingestion.units == "70" {
                    ingestion.units = "mg"
                }
            }
            try? viewContext.save()
        }
    }

    func migrateBenzydamineUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Benzydamine" && ingestion.units == "g" {
                    ingestion.units = "mg"
                    ingestion.dose = ingestion.dose * 1000
                }
            }
            try? viewContext.save()
        }
    }

    func migrateCannabisAndMushroomUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Cannabis" && ingestion.units == "mg" {
                    ingestion.units = "mg THC"
                }
                if ingestion.substanceName == "Psilocybin mushrooms" && ingestion.units == "mg" {
                    ingestion.units = "mg Psilocybin"
                }
            }

            let customUnitFetchRequest = CustomUnit.fetchRequest()
            let customUnits = (try? viewContext.fetch(customUnitFetchRequest)) ?? []
            for customUnit in customUnits {
                if customUnit.substanceName == "Cannabis" && customUnit.originalUnit == "mg" {
                    customUnit.originalUnit = "mg THC"
                }
                if customUnit.substanceName == "Psilocybin mushrooms" && customUnit.originalUnit == "mg" {
                    customUnit.originalUnit = "mg Psilocybin"
                }
            }

            try? viewContext.save()
        }
    }

    func migrateColors() {
        viewContext.performAndWait {
            let companionFetchRequest = SubstanceCompanion.fetchRequest()
            let allCompanions = (try? viewContext.fetch(companionFetchRequest)) ?? []
            for companion in allCompanions {
                companion.colorAsText = companion.colorAsText?.uppercased()
            }
            let timedNotesFetchRequest = TimedNote.fetchRequest()
            let allTimedNotes = (try? viewContext.fetch(timedNotesFetchRequest)) ?? []
            for timedNote in allTimedNotes {
                timedNote.colorAsText = timedNote.colorAsText?.uppercased()
            }
            try? viewContext.save()
        }
    }

    func saveViewContext() {
        saveWithRetry(context: viewContext, maxRetries: 3)
    }

    /// Saves context with automatic retry on failure
    private func saveWithRetry(context: NSManagedObjectContext, maxRetries: Int, currentRetry: Int = 0) {
        guard context.hasChanges else { return }

        do {
            try context.save()
            // Trigger iCloud sync after successful save
            triggerCloudKitSync()

            DispatchQueue.main.async {
                self.syncStatus = .synced
                self.lastSyncDate = Date()
            }
        } catch {
            print("⚠️ Save failed (attempt \(currentRetry + 1)/\(maxRetries)): \(error)")

            if currentRetry < maxRetries - 1 {
                // Wait briefly then retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    // Refresh and retry
                    context.refreshAllObjects()
                    self?.saveWithRetry(context: context, maxRetries: maxRetries, currentRetry: currentRetry + 1)
                }
            } else {
                // Final failure - log and update status
                print("❌ Save failed after \(maxRetries) attempts: \(error)")
                DispatchQueue.main.async {
                    self.syncStatus = .pendingChanges
                }
                assertionFailure("Failed to save viewContext after retries: \(error)")
            }
        }
    }

    /// Triggers an immediate CloudKit sync if iCloud sync is enabled
    func triggerCloudKitSync() {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else { return }

        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }

        // Process any pending remote changes first
        processRemoteChanges()

        // Refresh the view context to incorporate changes
        viewContext.refreshAllObjects()

        // Post a notification that can be observed by the CloudKit system
        NotificationCenter.default.post(
            name: NSNotification.Name("CloudKitSyncRequest"),
            object: nil
        )

        DispatchQueue.main.async {
            self.syncStatus = .synced
            self.lastSyncDate = Date()
        }

        print("☁️ iCloud sync triggered")
    }

    /// Forces an immediate full sync - call this if data seems out of sync
    func forceSync() {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        guard isICloudSyncEnabled else {
            print("⚠️ iCloud sync is disabled")
            return
        }

        print("☁️ Forcing full sync...")

        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }

        // Save any pending changes
        if viewContext.hasChanges {
            try? viewContext.save()
        }

        // Reset the view context to get fresh data
        viewContext.reset()

        // Process all history
        processRemoteChanges()

        // Refresh everything
        performFullSync()

        print("☁️ Force sync completed")
    }

    /// Resolves any pending conflicts by refreshing all objects from the store
    /// Call this if you suspect data might be out of sync
    func resolveConflicts() {
        viewContext.perform { [weak self] in
            guard let self = self else { return }

            // Reset the context to discard any unsaved changes and refresh from store
            if self.viewContext.hasChanges {
                // Save any local changes first
                do {
                    try self.viewContext.save()
                } catch {
                    print("⚠️ Error saving before conflict resolution: \(error)")
                }
            }

            // Refresh all objects to get the latest data
            self.viewContext.refreshAllObjects()

            print("☁️ Conflicts resolved - data refreshed from store")
        }
    }

    /// Returns the current sync status
    var iCloudSyncStatus: ICloudSyncStatus {
        let isEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        if !isEnabled {
            return .disabled
        }

        // Check if there are any pending changes
        if viewContext.hasChanges {
            return .pendingChanges
        }

        return .synced
    }










    public func getIngestionsBetween(startDate: Date, endDate: Date) -> [Ingestion] {
        let fetchRequest = Ingestion.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(time >= %@) AND (time <= %@)", startDate as NSDate, endDate as NSDate)
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getLatestActiveExperience() -> Experience? {
        let fetchRequest = Experience.fetchRequest()
        let minusThreeDays: TimeInterval = -3*24*60*60
        let startDate = Date.now.addingTimeInterval(minusThreeDays)
        fetchRequest.predicate = NSPredicate(format: "sortDate >= %@", startDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        let experiences = (try? viewContext.fetch(fetchRequest)) ?? []
        return experiences.first { experience in
            experience.isCurrent
        }
    }

    func getLatestExperience() -> Experience? {
        let fetchRequest = Experience.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        fetchRequest.fetchLimit = 1
        let experiences = (try? viewContext.fetch(fetchRequest)) ?? []
        return experiences.first
    }

    public func getSubstanceCompanions() -> [SubstanceCompanion] {
        let fetchRequest = SubstanceCompanion.fetchRequest()
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getCustomSubstance(name: String) -> CustomSubstance? {
        let fetchRequest = CustomSubstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        let results = try? viewContext.fetch(fetchRequest)
        return results?.first
    }
}



/// Represents the current iCloud sync status
enum ICloudSyncStatus {
    case disabled
    case synced
    case pendingChanges
    case syncing

    var description: String {
        switch self {
        case .disabled:
            return "iCloud sync is disabled"
        case .synced:
            return "All data synced"
        case .pendingChanges:
            return "Changes pending sync"
        case .syncing:
            return "Syncing..."
        }
    }

    var icon: String {
        switch self {
        case .disabled:
            return "icloud.slash"
        case .synced:
            return "checkmark.icloud"
        case .pendingChanges:
            return "arrow.triangle.2.circlepath.icloud"
        case .syncing:
            return "icloud.and.arrow.up"
        }
    }
}

