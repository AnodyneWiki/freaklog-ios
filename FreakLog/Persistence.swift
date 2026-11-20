@preconcurrency import CoreData //FIXME
import SwiftUI

struct PersistenceController {
    static let shared = PersistenceController()
    static let preview: PersistenceController = .init(inMemory: true)

    let container: NSPersistentCloudKitContainer

    private var isInitialized = false

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
    static let dynamicExperienceRangeHoursKey = "dynamicExperienceRangeHours"
    static let sendWebhooksEnabledKey = "sendWebhooksEnabled"
    static let webhookUsernameKey = "webhookUsername"
    static let webhookTemplateKey = "webhookTemplate"
    static let webhookIsHyperlinkedKey = "webhookIsHyperlinked"
    static let webhookSubstanceInfoUrlKey = "webhookSubstanceInfoUrl"
    static let defaultJournalViewKey = "defaultJournalView"
    static let isHidingJournalTabSwitcherKey = "isHidingJournalTabSwitcher"
    static let leaderboardServersKey = "leaderboardServers"
    static let leaderboardDeviceSeedKey = "leaderboardDeviceSeed"

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        let isICloudSyncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.isICloudSyncEnabledKey)
        container = NSPersistentCloudKitContainer(name: "Main")

        if !inMemory {
            container.persistentStoreDescriptions.forEach { description in
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

                if isICloudSyncEnabled {
                    #if DEBUG
                    let containerIdentifier = "iCloud.woof.freaklog-debug"
                    #else
                    let containerIdentifier = "iCloud.woof.freaklog"
                    #endif

                    let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                    description.cloudKitContainerOptions = cloudKitContainerOptions

                    description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                } else {
                    description.configuration = "Local"
                }
                
                #if APP_WIDGET
                description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
                #endif
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
        
        let didInitializeCloudKitSchemaKey = "didInitializeCloudKitSchema"
        if !UserDefaults.standard.bool(forKey: didInitializeCloudKitSchemaKey) {
            do {
                try container.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(true, forKey: didInitializeCloudKitSchemaKey)
            } catch {
            }
        }


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
            #if DEBUG
            let containerIdentifier = "iCloud.woof.freaklog-debug"
            #else
            let containerIdentifier = "iCloud.woof.freaklog"
            #endif
            let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
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
        let experienceDeleteRequest = Experience.fetchRequest()
        experienceDeleteRequest.includesPropertyValues = false
        let experiences = try context.fetch(experienceDeleteRequest)
        for exp in experiences {
            context.delete(exp)
        }
        let ingestionDeleteRequest = Ingestion.fetchRequest()
        ingestionDeleteRequest.includesPropertyValues = false
        let ingestions = try context.fetch(ingestionDeleteRequest)
        for ing in ingestions {
            context.delete(ing)
        }
        let customDeleteRequest = CustomSubstance.fetchRequest()
        customDeleteRequest.includesPropertyValues = false
        let customs = try context.fetch(customDeleteRequest)
        for cust in customs {
            context.delete(cust)
        }
        let companionDeleteRequest = SubstanceCompanion.fetchRequest()
        companionDeleteRequest.includesPropertyValues = false
        let companions = try context.fetch(companionDeleteRequest)
        for com in companions {
            context.delete(com)
        }
        let unitDeleteRequest = CustomUnit.fetchRequest()
        unitDeleteRequest.includesPropertyValues = false
        let customUnits = try context.fetch(unitDeleteRequest)
        for unit in customUnits {
            context.delete(unit)
        }
        let sprayDeleteRequest = Spray.fetchRequest()
        sprayDeleteRequest.includesPropertyValues = false
        let sprays = try context.fetch(sprayDeleteRequest)
        for spray in sprays {
            context.delete(spray)
        }
        let customRoaDeleteRequest = CustomRoa.fetchRequest()
        customRoaDeleteRequest.includesPropertyValues = false
        let customRoas = try context.fetch(customRoaDeleteRequest)
        for roa in customRoas {
            context.delete(roa)
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
        r.predicate = NSPredicate(format: "consumerName == nil OR consumerName == ''")
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

    static func experiencesRequest() -> NSFetchRequest<Experience> {
        let r = Experience.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
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

    static func standaloneCustomRoasRequest(for substanceName: String) -> NSFetchRequest<CustomRoa> {
        let r = CustomRoa.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \CustomRoa.administrationRoute, ascending: true)]
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "substanceName == %@", substanceName),
            NSPredicate(format: "customSubstance == nil"),
        ])
        return r
    }

    static func sprayRequest() -> NSFetchRequest<Spray> {
        let r = Spray.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Spray.creationDate, ascending: false)]
        return r
    }

    // MARK: - Instance Fetch Methods

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
        let r = Ingestion.fetchRequest()
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "time >= %@ AND time < %@", startDate as NSDate, endDate as NSDate),
            NSPredicate(format: "consumerName == nil OR consumerName == ''"),
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

    func getSubstanceCompanions() -> [SubstanceCompanion] {
        let fetchRequest = SubstanceCompanion.fetchRequest()
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getCustomSubstance(name: String) -> CustomSubstance? {
        let fetchRequest = CustomSubstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        let results = try? viewContext.fetch(fetchRequest)
        return results?.first
    }

    func getCustomRoa(for substanceName: String, route: AdministrationRoute) -> CustomRoa? {
        let fetchRequest = CustomRoa.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "substanceName == %@", substanceName),
            NSPredicate(format: "administrationRoute == %@", route.rawValue),
            NSPredicate(format: "customSubstance == nil"),
        ])
        return (try? viewContext.fetch(fetchRequest))?.first
    }

    // Uniform interface: resolves dose for any substance name (PW or custom),
    // applying standalone custom overrides with priority over built-in PW data.
    func resolvedDose(for substanceName: String, route: AdministrationRoute) -> RoaDose? {
        if let pw = SubstanceRepo.shared.getSubstance(name: substanceName) {
            return getCustomRoa(for: substanceName, route: route)?.roaDose
                ?? pw.getDose(for: route)
        }
        return getCustomSubstance(name: substanceName)?.getRoaDose(for: route)
    }

    func resolvedDuration(for substanceName: String, route: AdministrationRoute) -> RoaDuration? {
        if let pw = SubstanceRepo.shared.getSubstance(name: substanceName) {
            return getCustomRoa(for: substanceName, route: route)?.roaDuration
                ?? pw.getDuration(for: route)
        }
        return getCustomSubstance(name: substanceName)?.getRoaDuration(for: route)
    }

    func renameSubstance(from oldName: String, to newName: String) {
        let ctx = viewContext
        let ingFetch = Ingestion.fetchRequest()
        ingFetch.predicate = NSPredicate(format: "substanceName == %@", oldName)
        ((try? ctx.fetch(ingFetch)) ?? []).forEach { $0.substanceName = newName }

        let compFetch = SubstanceCompanion.fetchRequest()
        compFetch.predicate = NSPredicate(format: "substanceName == %@", oldName)
        ((try? ctx.fetch(compFetch)) ?? []).forEach { $0.substanceName = newName }

        let unitFetch = CustomUnit.fetchRequest()
        unitFetch.predicate = NSPredicate(format: "substanceName == %@", oldName)
        ((try? ctx.fetch(unitFetch)) ?? []).forEach { $0.substanceName = newName }

        let roaFetch = CustomRoa.fetchRequest()
        roaFetch.predicate = NSPredicate(format: "substanceName == %@", oldName)
        ((try? ctx.fetch(roaFetch)) ?? []).forEach { $0.substanceName = newName }
    }
}
