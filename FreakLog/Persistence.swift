@preconcurrency import CoreData //FIXME
import SwiftUI

struct PersistenceController {
    static let shared = PersistenceController()
    static let preview: PersistenceController = .init(inMemory: true)

    let container: NSPersistentCloudKitContainer
    let roaCache: ResolvedRoaCache
    let overrideCache: SubstanceOverrideCache

    private var isInitialized = false

    static let needsToSeeWelcomeKey = "needsToSeeWelcome"
    static let isEyeOpenKey1 = "isEyeOpen"
    static let isEyeOpenKey2 = "isEyeOpen2"
    static let hasToUnlockAppKey = "hasToUnlockApp"
    static let lockTimeOptionKey = "lockTimeOption"
    static let lastUnlockDateKey = "lastDate"
    static let hiddenTabsKey = "hiddenTabs"
    static let timeDisplayStyleKey = "timeDisplayStyle"
    static let isHidingDosageDotsKey = "isHidingDosageDots"
    static let isHidingToleranceChartInExperienceKey = "isHidingToleranceChartInExperience"
    static let isHidingSubstanceInfoInExperienceKey = "isHidingSubstanceInfoInExperience"
    static let areRedosesDrawnIndividuallyKey = "areRedosesDrawnIndividually"
    static let shouldAutomaticallyStartLiveActivityKey = "shouldAutomaticallyStartLiveActivity"
    static let independentSubstanceHeightKey = "independentSubstanceHeight"
    static let fabButtonPositionKey = "fabButtonPosition"
    static let isICloudSyncEnabledKey = "isICloudSyncEnabled"
    static let dynamicExperienceRangeHoursKey = "dynamicExperienceRangeHours"
    static let sendWebhooksEnabledKey = "sendWebhooksEnabled"
    static let webhookUsernameKey = "webhookUsername"
    static let webhookTemplateKey = "webhookTemplate"
    static let webhookNoteTemplateKey = "webhookNoteTemplate"
    static let webhookIsHyperlinkedKey = "webhookIsHyperlinked"
    static let webhookSubstanceInfoUrlKey = "webhookSubstanceInfoUrl"
    static let isAnodyneAutoLoadEnabledKey = "isAnodyneAutoLoadEnabled"
    static let doseSourceKey = "doseSource"
    static let anodyneInstanceURLKey = "anodyneInstanceURL"
    static let defaultJournalViewKey = "defaultJournalView"
    static let isHidingJournalTabSwitcherKey = "isHidingJournalTabSwitcher"
    static let leaderboardServersKey = "leaderboardServers"
    static let leaderboardDeviceSeedKey = "leaderboardDeviceSeed"
    static let isOpenLastExperienceSiriTipVisibleKey = "isOpenLastExperienceSiriTipVisible"
    static let isSearchSubstanceSiriTipVisibleKey = "isSearchSubstanceSiriTipVisible"
    static let isAddIngestionSiriTipVisibleKey = "isAddIngestionSiriTipVisible"
    static let hasBeenMigrated2Key = "hasBeenMigrated2"
    static let hasBeenMigrated3Key = "hasBeenMigrated3"
    static let hasBeenMigrated4Key = "hasBeenMigrated4"
    static let hasBeenMigrated5Key = "hasBeenMigrated5"
    static let hasBeenMigrated6Key = "hasBeenMigrated6"
    static let hasBeenMigrated7Key = "hasBeenMigrated7"
    static let hasBeenMigrated8Key = "hasBeenMigrated8"
    static let openUntilRatedCountKey = "openUntilRatedCount"
    static let didInitializeCloudKitSchemaKey = "didInitializeCloudKitSchema"

    #if DEBUG
    static let cloudKitContainerIdentifier = "iCloud.woof.freaklog-debug"
    #else
    static let cloudKitContainerIdentifier = "iCloud.woof.freaklog"
    #endif

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        container = NSPersistentCloudKitContainer(name: "Main")
        roaCache = ResolvedRoaCache(context: container.viewContext)
        overrideCache = SubstanceOverrideCache(context: container.viewContext)
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: container.viewContext,
            queue: nil
        ) { notification in
            guard let context = notification.object as? NSManagedObjectContext else { return }
            Experience.updateSortDates(beforeSaving: context)
        }

        if !inMemory {
            container.persistentStoreDescriptions.forEach { description in
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

                if isICloudSyncEnabled {
                    let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
                    description.cloudKitContainerOptions = cloudKitContainerOptions

                    description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                } else {
                    description.configuration = "Local"
                }
            }
        }

        if inMemory {
            loadInMemoryStores(description: container.persistentStoreDescriptions.first)
            isInitialized = true
        }
    }

    public func loadData(_ app: UIApplication) {
        tryLoadPersistentStores(app)
    }

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

    private func tryLoadPersistentStores(_ app: UIApplication) {
        if isInitialized { return }
        container.loadPersistentStores { description, error in
            if let error = error {
                let nsError = error as NSError
                if (nsError.domain == "NSCocoaErrorDomain" && nsError.code == 256 && nsError.userInfo["NSSQLiteErrorDomain"] as? Int == 23) {
                    exit(0)
                }
                else {
                    fatalError("Failed to load Core Data stack: \(error)")
                }
            }
        }

        
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Pushes the schema to the CloudKit development environment. This blocks launch and fails against
        // production and without sync enabled (retrying on every launch), so only debug builds with sync try it.
        #if DEBUG
        let isSyncConfigured = container.persistentStoreDescriptions.contains { $0.cloudKitContainerOptions != nil }
        if isSyncConfigured, !UserDefaults.standard.bool(forKey: Self.didInitializeCloudKitSchemaKey) {
            do {
                try container.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(true, forKey: Self.didInitializeCloudKitSchemaKey)
            } catch {
                print("Failed to initialize CloudKit schema: \(error)")
            }
        }
        #endif


        return
    }

    func updateCloudKitSyncStatus(_ enabled: Bool) {
        
        saveViewContext()
        
        guard let store = container.persistentStoreCoordinator.persistentStores.first,
              let url = store.url else {
            return
        }

        guard let description = container.persistentStoreDescriptions.first else {
             return
        }

        if enabled {
            let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
            description.cloudKitContainerOptions = cloudKitContainerOptions
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.configuration = nil
        } else {
            description.cloudKitContainerOptions = nil
            description.setOption(false as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.configuration = "Local"
        }

        do {
            try container.persistentStoreCoordinator.remove(store)
        } catch {
            return
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func deleteEverything(blockContext: NSManagedObjectContext? = nil) throws {
        let context = blockContext ?? viewContext
        // Entities not reached via cascade delete rules are listed explicitly
        let entityNames = [
            "Experience", "Ingestion", "CustomSubstance", "SubstanceCompanion", "CustomUnit", "Spray", "CustomRoa",
            "SubstanceOverride", "Formulation",
        ]
        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.includesPropertyValues = false
            try context.fetch(request).forEach(context.delete)
        }
        try context.save()

        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        if !isICloudSyncEnabled {
            let purgeHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: Date())
            do {
                try context.execute(purgeHistoryRequest)
            } catch {
            }
        }
    }

    // One-off data fixes, each run once and remembered under its key, in order
    func runPendingMigrations() {
        let defaults = UserDefaults.standard
        let migrations: [(key: String, run: () -> Void)] = [
            (Self.hasBeenMigrated2Key, {
                self.migrateCompanionsAndExperienceSortDates()
                defaults.set(defaults.bool(forKey: Self.isEyeOpenKey1), forKey: Self.isEyeOpenKey2)
            }),
            (Self.hasBeenMigrated3Key, migrateIngestionNamesAndUnits),
            (Self.hasBeenMigrated4Key, migrateColors),
            (Self.hasBeenMigrated5Key, migrateBenzydamineUnits),
            (Self.hasBeenMigrated6Key, migrateCannabisAndMushroomUnits),
            (Self.hasBeenMigrated7Key, migrateRemoveDuplicateCompanions),
            (Self.hasBeenMigrated8Key, migrateFillPartialSubstanceOverrides),
        ]
        for migration in migrations where !defaults.bool(forKey: migration.key) {
            migration.run()
            defaults.set(true, forKey: migration.key)
        }
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

    // Overrides of PsychonautWiki data with only some phases or dose levels left the rest undrawn
    func migrateFillPartialSubstanceOverrides() {
        viewContext.performAndWait {
            for roa in getAllStandaloneCustomRoas() {
                guard let name = roa.substanceName, SubstanceRepo.shared.getSubstance(name: name) != nil else { continue }
                let values = CustomRoaCodable(roa: roa)
                let filled = values.fillingGaps(from: .psychonautWikiValues(for: name, route: values.administrationRoute))
                if filled != values {
                    filled.apply(to: roa)
                }
            }
            try? viewContext.save()
        }
    }

    func migrateRemoveDuplicateCompanions() {
        viewContext.performAndWait {
            let companionFetchRequest = SubstanceCompanion.fetchRequest()
            let allCompanions = (try? viewContext.fetch(companionFetchRequest)) ?? []

            var companionsByName: [String: [SubstanceCompanion]] = [:]
            for companion in allCompanions {
                guard let name = companion.substanceName else { continue }
                companionsByName[name, default: []].append(companion)
            }

            for (_, companions) in companionsByName where companions.count > 1 {
                let keeper = companions[0]
                let duplicates = companions[1...]

                for duplicate in duplicates {
                    if let ingestions = duplicate.ingestions as? Set<Ingestion> {
                        for ingestion in ingestions {
                            ingestion.substanceCompanion = keeper
                        }
                    }
                    viewContext.delete(duplicate)
                }
            }

            try? viewContext.save()
        }
    }

    // MARK: - FetchRequest Factories
    // Single source of truth for all CoreData queries. Use these in @FetchRequest(fetchRequest:),
    // NSFetchedResultsController, and the instance fetch methods below.

    static func ingestionsRequest() -> NSFetchRequest<Ingestion> {
        let r = Ingestion.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)]
        return r
    }

    static func personalIngestionsRequest() -> NSFetchRequest<Ingestion> {
        let r = ingestionsRequest()
        // Matches Ingestion.isMine: no name, or one made of spaces only
        r.predicate = NSPredicate(format: "consumerName == nil OR consumerName MATCHES %@", "\\h*")
        return r
    }

    static func personalIngestionsRequest(for substanceName: String) -> NSFetchRequest<Ingestion> {
        let r = personalIngestionsRequest()
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            r.predicate!,
            NSPredicate(format: "substanceName == %@", substanceName),
        ])
        return r
    }

    static func ingestionsRequest(for date: Date) -> NSFetchRequest<Ingestion> {
        let r = ingestionsRequest()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? date
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "time > %@", startOfDay as NSDate),
            NSPredicate(format: "time < %@", endOfDay as NSDate),
        ])
        return r
    }

    static func recentIngestionsRequest(limit: Int) -> NSFetchRequest<Ingestion> {
        let r = ingestionsRequest()
        r.fetchLimit = limit
        return r
    }

    static func ingestionsWithNotesRequest(limit: Int = 15) -> NSFetchRequest<Ingestion> {
        let r = ingestionsRequest()
        r.predicate = NSPredicate(format: "note.length > 0")
        r.fetchLimit = limit
        return r
    }

    // Prefetching avoids one fault per experience when every experience's ingestions are read
    static func experiencesRequest(prefetchingIngestions: Bool = false) -> NSFetchRequest<Experience> {
        let r = Experience.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        if prefetchingIngestions {
            r.relationshipKeyPathsForPrefetching = ["ingestions"]
        }
        return r
    }

    static func customSubstancesRequest() -> NSFetchRequest<CustomSubstance> {
        let r = CustomSubstance.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomSubstance.name, ascending: true)]
        return r
    }

    static func activeCustomUnitsRequest(filter: String = "") -> NSFetchRequest<CustomUnit> {
        let r = CustomUnit.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomUnit.creationDate, ascending: false)]
        let archivedPredicate = NSPredicate(format: "isArchived == %@", NSNumber(value: false))
        if filter.isEmpty {
            r.predicate = archivedPredicate
        } else {
            let searchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "name CONTAINS[c] %@", filter),
                NSPredicate(format: "substanceName CONTAINS[c] %@", filter),
                NSPredicate(format: "substanceName IN %@", shared.substanceNames(withDisplayNameContaining: filter)),
                NSPredicate(format: "unit CONTAINS[c] %@", filter),
                NSPredicate(format: "note CONTAINS[c] %@", filter),
                NSPredicate(format: "administrationRoute CONTAINS[c] %@", filter),
            ])
            r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [archivedPredicate, searchPredicate])
        }
        return r
    }

    static func archivedCustomUnitsRequest() -> NSFetchRequest<CustomUnit> {
        let r = CustomUnit.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomUnit.creationDate, ascending: false)]
        r.predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: true))
        return r
    }

    static func activeCustomUnitsRequest(for substanceName: String) -> NSFetchRequest<CustomUnit> {
        let r = CustomUnit.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomUnit.creationDate, ascending: false)]
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == %@", NSNumber(value: false)),
            NSPredicate(format: "substanceName == %@", substanceName),
        ])
        return r
    }

    static func substanceCompanionsRequest() -> NSFetchRequest<SubstanceCompanion> {
        let r = SubstanceCompanion.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \SubstanceCompanion.substanceName, ascending: true)]
        return r
    }

    static func activeWebhookPresetsRequest() -> NSFetchRequest<WebhookPreset> {
        let r = WebhookPreset.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \WebhookPreset.creationDate, ascending: true)]
        r.predicate = NSPredicate(format: "isArchived == NO")
        return r
    }

    static func archivedWebhookPresetsRequest() -> NSFetchRequest<WebhookPreset> {
        let r = WebhookPreset.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \WebhookPreset.creationDate, ascending: true)]
        r.predicate = NSPredicate(format: "isArchived == YES")
        return r
    }

    static func enabledWebhookPresetsRequest() -> NSFetchRequest<WebhookPreset> {
        let r = WebhookPreset.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \WebhookPreset.name, ascending: true)]
        r.predicate = NSPredicate(format: "isEnabled == YES")
        return r
    }

    // Matches both PW overrides and custom substance roas (older ones only carry the parent's name).
    static func customRoasRequest(for substanceName: String) -> NSFetchRequest<CustomRoa> {
        let r = CustomRoa.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomRoa.administrationRoute, ascending: true)]
        r.predicate = NSPredicate(
            format: "substanceName == %@ OR (substanceName == nil AND customSubstance.name == %@)",
            substanceName,
            substanceName
        )
        return r
    }

    static func formulationsRequest() -> NSFetchRequest<Formulation> {
        let r = Formulation.fetchRequest()
        r.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))),
        ]
        return r
    }

    static func timedNotesRequest() -> NSFetchRequest<TimedNote> {
        let r = TimedNote.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \TimedNote.time, ascending: false)]
        return r
    }

    static func sprayRequest() -> NSFetchRequest<Spray> {
        let r = Spray.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Spray.creationDate, ascending: false)]
        return r
    }

    // MARK: - Instance Fetch Methods

    func getIngestionCount() -> Int {
        (try? viewContext.count(for: Ingestion.fetchRequest())) ?? 0
    }

    func getAllIngestions() -> [Ingestion] {
        (try? viewContext.fetch(Ingestion.fetchRequest())) ?? []
    }

    func getRecentIngestions(limit: Int = 1000) -> [Ingestion] {
        (try? viewContext.fetch(Self.recentIngestionsRequest(limit: limit))) ?? []
    }

    func getIngestionsWithNotes(limit: Int = 15) -> [Ingestion] {
        (try? viewContext.fetch(Self.ingestionsWithNotesRequest(limit: limit))) ?? []
    }

    func getAllExperiences() -> [Experience] {
        (try? viewContext.fetch(Self.experiencesRequest())) ?? []
    }

    func getExperiences(near date: Date) -> [Experience] {
        let window: TimeInterval = 60 * 60 * 60
        let r = Self.experiencesRequest()
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "sortDate > %@", date.addingTimeInterval(-window) as NSDate),
            NSPredicate(format: "sortDate < %@", date.addingTimeInterval(window) as NSDate),
        ])
        return (try? viewContext.fetch(r)) ?? []
    }

    func getAllCustomSubstances() -> [CustomSubstance] {
        (try? viewContext.fetch(Self.customSubstancesRequest())) ?? []
    }

    func getActiveCustomUnits() -> [CustomUnit] {
        (try? viewContext.fetch(Self.activeCustomUnitsRequest())) ?? []
    }

    func getAllCustomUnits() -> [CustomUnit] {
        (try? viewContext.fetch(CustomUnit.fetchRequest())) ?? []
    }

    func getAllFormulations() -> [Formulation] {
        (try? viewContext.fetch(Self.formulationsRequest())) ?? []
    }

    func getAllStandaloneCustomRoas() -> [CustomRoa] {
        let r = CustomRoa.fetchRequest()
        r.predicate = NSPredicate(format: "customSubstance == nil")
        return (try? viewContext.fetch(r)) ?? []
    }

    func getSubstanceCompanion(for substanceName: String) -> SubstanceCompanion? {
        let r = SubstanceCompanion.fetchRequest()
        r.predicate = NSPredicate(format: "substanceName == %@", substanceName)
        r.fetchLimit = 1
        return (try? viewContext.fetch(r))?.first
    }

    func getRecentLocations(limit: Int = 15) -> [ExperienceLocation] {
        let r = ExperienceLocation.fetchRequest()
        r.sortDescriptors = [
            NSSortDescriptor(keyPath: \ExperienceLocation.ingestion?.time, ascending: false),
            NSSortDescriptor(keyPath: \ExperienceLocation.legacyExperience?.creationDate, ascending: false),
        ]
        r.fetchLimit = limit
        return (try? viewContext.fetch(r)) ?? []
    }

    func getPersonalIngestions(from startDate: Date, to endDate: Date) -> [Ingestion] {
        let r = Self.personalIngestionsRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: true)]
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            r.predicate!,
            NSPredicate(format: "time >= %@ AND time < %@", startDate as NSDate, endDate as NSDate),
        ])
        return (try? viewContext.fetch(r)) ?? []
    }

    func saveViewContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                assertionFailure("Failed to save viewContext: \(error)")
            }
        }
    }

    func getIngestionsBetween(startDate: Date, endDate: Date) -> [Ingestion] {
        let fetchRequest = Ingestion.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(time >= %@) AND (time <= %@)", startDate as NSDate, endDate as NSDate)
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getLatestActiveExperience() -> Experience? {
        let fetchRequest = Self.experiencesRequest()
        let minusThreeDays: TimeInterval = -3*24*60*60
        let startDate = Date.now.addingTimeInterval(minusThreeDays)
        fetchRequest.predicate = NSPredicate(format: "sortDate >= %@", startDate as NSDate)
        let experiences = (try? viewContext.fetch(fetchRequest)) ?? []
        return experiences.first { experience in
            experience.isCurrent
        }
    }

    func getLatestExperience() -> Experience? {
        let fetchRequest = Self.experiencesRequest()
        fetchRequest.fetchLimit = 1
        return (try? viewContext.fetch(fetchRequest))?.first
    }

    func getSubstanceCompanions() -> [SubstanceCompanion] {
        (try? viewContext.fetch(Self.substanceCompanionsRequest())) ?? []
    }

    func getCustomSubstance(name: String) -> CustomSubstance? {
        let fetchRequest = CustomSubstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        fetchRequest.fetchLimit = 1
        return (try? viewContext.fetch(fetchRequest))?.first
    }

    func getCustomRoa(for substanceName: String, route: AdministrationRoute) -> CustomRoa? {
        let r = Self.customRoasRequest(for: substanceName)
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            r.predicate!,
            NSPredicate(format: "administrationRoute == %@", route.rawValue),
        ])
        r.fetchLimit = 1
        return (try? viewContext.fetch(r))?.first
    }

    // Single entry point for dose/duration of any substance (PW or custom).
    // Custom data takes priority over PW data, per field.
    // The user's data first, then PsychonautWiki's, then AnodyneWiki's, when it was loaded for the substance before
    func resolvedRoa(for substanceName: String, route: AdministrationRoute) -> ResolvedRoa {
        let custom = roaCache.entry(for: substanceName, route: route)
        let pw = SubstanceRepo.shared.getSubstance(name: substanceName)
        let anodyne = AnodyneFallbackStore.shared
        return ResolvedRoa(
            dose: custom?.dose ?? pw?.getDose(for: route) ?? anodyne.dose(for: substanceName, route: route),
            duration: custom?.duration ?? pw?.getDuration(for: route) ?? anodyne.duration(for: substanceName, route: route)
        )
    }

    // Whether a route's dose is AnodyneWiki's, because the user and PsychonautWiki have none
    func isDoseFromAnodyneWiki(for substanceName: String, route: AdministrationRoute) -> Bool {
        roaCache.entry(for: substanceName, route: route)?.dose == nil
            && SubstanceRepo.shared.getSubstance(name: substanceName)?.getDose(for: route) == nil
            && AnodyneFallbackStore.shared.dose(for: substanceName, route: route) != nil
    }

    // Whether a route's duration is AnodyneWiki's, because the user and PsychonautWiki have none
    func isDurationFromAnodyneWiki(for substanceName: String, route: AdministrationRoute) -> Bool {
        roaCache.entry(for: substanceName, route: route)?.duration == nil
            && SubstanceRepo.shared.getSubstance(name: substanceName)?.getDuration(for: route) == nil
            && AnodyneFallbackStore.shared.duration(for: substanceName, route: route) != nil
    }

    func resolvedDose(for substanceName: String, route: AdministrationRoute) -> RoaDose? {
        resolvedRoa(for: substanceName, route: route).dose
    }

    func resolvedDuration(for substanceName: String, route: AdministrationRoute) -> RoaDuration? {
        resolvedRoa(for: substanceName, route: route).duration
    }

    func renameSubstance(from oldName: String, to newName: String) {
        for entityName in [
            "Ingestion", "SubstanceCompanion", "CustomUnit", "CustomRoa", "SubstanceOverride", "FormulationComponent",
        ] {
            let r = NSFetchRequest<NSManagedObject>(entityName: entityName)
            r.predicate = NSPredicate(format: "substanceName == %@", oldName)
            ((try? viewContext.fetch(r)) ?? []).forEach { $0.setValue(newName, forKey: "substanceName") }
        }
    }
}

struct ResolvedRoa {
    let dose: RoaDose?
    let duration: RoaDuration?
}

// In-memory copy of all CustomRoa data, keyed by substance name and route. The table is small,
// so it is loaded at once and dropped whenever a CustomRoa or CustomSubstance changes.
final class ResolvedRoaCache: @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let lock = NSLock()
    private var entries: [String: [AdministrationRoute: ResolvedRoa]]?
    private var observer: NSObjectProtocol?

    init(context: NSManagedObjectContext) {
        self.context = context
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: nil
        ) { [weak self] notification in
            guard Self.affectsCustomRoas(notification) else { return }
            self?.invalidate()
        }
    }

    func entry(for substanceName: String, route: AdministrationRoute) -> ResolvedRoa? {
        lock.lock()
        defer { lock.unlock() }
        if entries == nil {
            entries = load()
        }
        return entries?[substanceName]?[route]
    }

    private func invalidate() {
        lock.lock()
        entries = nil
        lock.unlock()
    }

    private func load() -> [String: [AdministrationRoute: ResolvedRoa]] {
        var result: [String: [AdministrationRoute: ResolvedRoa]] = [:]
        context.performAndWait {
            let roas = (try? context.fetch(CustomRoa.fetchRequest())) ?? []
            for roa in roas {
                guard let name = roa.substanceNameResolved, roa.hasData else { continue }
                result[name, default: [:]][roa.administrationRouteUnwrapped] = ResolvedRoa(
                    dose: roa.roaDose,
                    duration: roa.roaDuration
                )
            }
        }
        return result
    }

    private static func affectsCustomRoas(_ notification: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        return keys.contains { key in
            (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains {
                $0 is CustomRoa || $0 is CustomSubstance
            } ?? false
        } || notification.userInfo?[NSInvalidatedAllObjectsKey] != nil
    }
}
