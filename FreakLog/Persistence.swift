import CoreData
import CloudKit
import SwiftUI

enum PersistenceConfiguration {
    enum Keys {
        static let needsToSeeWelcome = "needsToSeeWelcome"
        static let isEyeOpenKey1 = "isEyeOpen"
        static let isEyeOpenKey2 = "isEyeOpen2"
        static let timeDisplayStyle = "timeDisplayStyle"
        static let timeDisplayStyleDurationSection = "timeDisplayStyleDurationSection"
        static let isHidingDosageDots = "isHidingDosageDots"
        static let isHidingToleranceChartInExperience = "isHidingToleranceChartInExperience"
        static let isHidingSubstanceInfoInExperience = "isHidingSubstanceInfoInExperience"
        static let areRedosesDrawnIndividually = "areRedosesDrawnIndividually"
        static let shouldAutomaticallyStartLiveActivity = "shouldAutomaticallyStartLiveActivity"
        static let independentSubstanceHeight = "independentSubstanceHeight"
        static let lastIngestionTimeOfExperienceWhereAddIngestionTapped = "lastIngestionTimeOfExperienceWhereAddIngestionTapped"
        static let clonedIngestionTime = "clonedIngestionTimeKey"
        static let fabButtonPosition = "fabButtonPosition"
        static let isICloudSyncEnabled = "isICloudSyncEnabled"
    }

    static let modelName = "Main"
    static let cloudKitContainerIdentifier = "iCloud.woof.freaklog"
}

@Observable
final class PersistenceController {
    static let shared = PersistenceController()
    nonisolated static let preview: PersistenceController = .init(inMemory: true)

    let container: NSPersistentCloudKitContainer
    var syncStatus: ICloudSyncStatus = .disabled
    var lastSyncDate: Date?

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    @MainActor
    var iCloudSyncStatus: ICloudSyncStatus {
        let isEnabled = UserDefaults.standard.bool(forKey: PersistenceConfiguration.Keys.isICloudSyncEnabled)
        if !isEnabled {
            return .disabled
        }

        if viewContext.hasChanges {
            return .pendingChanges
        }

        return .synced
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: PersistenceConfiguration.modelName)

        if inMemory {
            loadInMemoryStores()
            return
        }

        configureStoreDescription()
        loadStores()
    }

    private func configureStoreDescription() {
        guard let description = container.persistentStoreDescriptions.first else { return }

#if APP_WIDGET
        description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
#endif

        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceConfiguration.Keys.isICloudSyncEnabled)

        if isICloudSyncEnabled {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceConfiguration.cloudKitContainerIdentifier)
            description.cloudKitContainerOptions = options
            syncStatus = .synced
        } else {
            description.cloudKitContainerOptions = nil
            syncStatus = .disabled
        }
    }

    private func loadStores() {
        container.loadPersistentStores { [weak self] _, error in
            if let error {
                fatalError("Failed to load Core Data stack: \(error)")
            }

            Task { @MainActor in
                self?.setupContext()
            }
        }
    }

    private func loadInMemoryStores() {
        guard let description = container.persistentStoreDescriptions.first else { return }
        description.type = NSInMemoryStoreType

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load in-memory Core Data stack: \(error)")
            }
        }

        setupContext()
    }

    private func setupContext() {
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    @MainActor
    func setICloudSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: PersistenceConfiguration.Keys.isICloudSyncEnabled)

        if viewContext.hasChanges {
            try? viewContext.save()
        }

        guard let store = container.persistentStoreCoordinator.persistentStores.first,
              let storeURL = store.url else {
            print("Failed to get current store for iCloud sync switch")
            return
        }

        do {
            try container.persistentStoreCoordinator.remove(store)
        } catch {
            print("Failed to remove store: \(error)")
            return
        }

        let newDescription = NSPersistentStoreDescription(url: storeURL)

        if enabled {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceConfiguration.cloudKitContainerIdentifier)
            newDescription.cloudKitContainerOptions = options
        }

        container.persistentStoreCoordinator.addPersistentStore(with: newDescription) { [weak self] _, error in
            if let error {
                print("Failed to add store with new configuration: \(error)")
                return
            }

            Task { @MainActor in
                self?.syncStatus = enabled ? .synced : .disabled
                self?.lastSyncDate = enabled ? Date() : nil
            }
        }
    }

    public func loadData(_ app: UIApplication) {
        // NSPersistentCloudKitContainer handles loading automatically
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


    func saveViewContext() {
        do {
            try viewContext.save()
        } catch {
            print("Failed to save view context: \(error)")
        }
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

