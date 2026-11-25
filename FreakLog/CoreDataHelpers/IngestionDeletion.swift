import CoreData

// Deleting ingestions has effects outside CoreData: sent webhook messages are removed and
// leaderboard servers are told about the deletion. Delete ingestions, timed notes and experiences through here.
// The local delete happens right away; the network cleanup runs afterwards in the background.
@MainActor
enum IngestionDeletion {
    @discardableResult
    static func delete(ingestions: [Ingestion], returningStock: Bool = false) async -> Bool {
        await delete(ingestions, returningStock: returningStock)
    }

    @discardableResult
    static func delete(timedNote: TimedNote) async -> Bool {
        await delete([timedNote])
    }

    @discardableResult
    static func delete(experience: Experience) async -> Bool {
        await delete([experience])
    }

    @discardableResult
    static func delete(customUnit: CustomUnit) async -> Bool {
        await delete([customUnit])
    }

    static let failureNotification = Notification.Name("JournalDeletionFailed")

    private static func delete(_ objects: [NSManagedObject], returningStock: Bool = false) async -> Bool {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let identifiers = try PersistenceController.withJournalStoreWrite {
                let rootObjects = try objects.filter { !$0.isDeleted }.flatMap { object -> [NSManagedObject] in
                    let stored = try PersistenceController.journalObject(object, in: context)
                    if let ingestion = stored as? Ingestion, ingestion.isUnconfirmed {
                        return ingestion.pendingConfirmationEntries
                    }
                    return [stored]
                }.uniqued()
                var ingestions: [Ingestion] = []
                var notes: [TimedNote] = []
                for object in rootObjects {
                    switch object {
                    case let ingestion as Ingestion:
                        ingestions.append(ingestion)
                    case let note as TimedNote:
                        notes.append(note)
                    case let experience as Experience:
                        ingestions += experience.ingestionsSorted
                        notes += experience.timedNotesSorted
                    case let unit as CustomUnit:
                        ingestions += unit.ingestionsUnwrapped
                    default:
                        break
                    }
                }
                let identifiers = ingestions.filter { !$0.isUnconfirmed }.compactMap(\.identifier)
                if returningStock {
                    guard rootObjects.count == 1, let ingestion = rootObjects.first as? Ingestion else {
                        throw InventoryError.cannotReverseUse
                    }
                    try Inventory.stageUsageReversal(for: ingestion)
                }
                WebhookManager.stageMessageDeletion(for: ingestions, timedNotes: notes, in: context)
                rootObjects.forEach(context.delete)
                try PersistenceController.saveJournalChanges(in: context)
                return identifiers
            }
            didDelete(identifiers: identifiers)
            return true
        } catch {
            let message = (error as? InventoryError)?.errorDescription ?? "Couldn't delete journal data"
            NotificationCenter.default.post(name: failureNotification, object: message)
            return false
        }
    }

    static func didDelete(identifiers: [UUID]) {
        LeaderboardSyncManager.shared.queueDeletions(identifiers: identifiers)
        Task {
            async let webhooks = WebhookManager.shared.retryPendingDeletions()
            async let leaderboards: Void = LeaderboardSyncManager.shared.retryPendingDeletions()
            async let routines: Void = RoutineSchedules.shared.refresh()
            if !(await webhooks) {
                NotificationCenter.default.post(name: failureNotification, object: "Webhook cleanup will retry")
            }
            await leaderboards
            await routines
        }
    }
}
