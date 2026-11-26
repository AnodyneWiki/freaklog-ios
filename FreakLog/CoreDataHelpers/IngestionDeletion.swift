import CoreData

// Deleting ingestions has effects outside CoreData: sent webhook messages are removed and
// leaderboard servers are told about the deletion. Delete ingestions, timed notes and experiences through here.
// The local delete happens right away; the network cleanup runs afterwards in the background.
@MainActor
enum IngestionDeletion {
    struct Request {
        private let selectedID: NSManagedObjectID
        private let stockUseID: NSManagedObjectID?
        let canReturnStock: Bool

        var hasStockUse: Bool { stockUseID != nil }
        let name: String
        let date: Date?
        let amount: String

        init(_ ingestion: Ingestion) {
            selectedID = ingestion.objectID
            stockUseID = ingestion.stockChange?.objectID
            canReturnStock = ingestion.stockChange?.canReverseUse == true
            name = ingestion.substanceDisplayName
            date = ingestion.time
            amount = ingestion.customUnitDose?.doseDescription
                ?? ingestion.doseUnwrapped?.doseDescription(
                    units: ingestion.unitsUnwrapped,
                    isEstimate: ingestion.isEstimate,
                    standardDeviation: ingestion.estimatedDoseStandardDeviationUnwrapped
                )
                ?? String(localized: "Unknown amount")
        }

        func requiresConfirmation(preferenceEnabled: Bool) -> Bool {
            preferenceEnabled || hasStockUse
        }

        func resolve(in context: NSManagedObjectContext) throws -> [Ingestion] {
            guard !selectedID.isTemporaryID,
                  let ingestion = try? context.existingObject(with: selectedID) as? Ingestion,
                  !ingestion.isDeleted,
                  ingestion.stockChange?.objectID == stockUseID else {
                throw DeletionError.entryUnavailable
            }
            return [ingestion]
        }
    }

    private enum DeletionError: LocalizedError {
        case entryUnavailable

        var errorDescription: String? {
            String(localized: "This ingestion is no longer available. Review the journal before deleting.")
        }
    }

    @discardableResult
    static func delete(_ request: Request, returningStock: Bool = false) async -> Bool {
        await delete(returningStock: returningStock) { context in
            try request.resolve(in: context)
        }
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

    private static func delete(_ objects: [NSManagedObject]) async -> Bool {
        await delete { context in
            try objects.filter { !$0.isDeleted }.map { try PersistenceController.journalObject($0, in: context) }
        }
    }

    private static func delete(
        returningStock: Bool = false, resolve: (NSManagedObjectContext) throws -> [NSManagedObject]
    ) async -> Bool {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let identifiers = try PersistenceController.withJournalStoreWrite {
                let rootObjects = try resolve(context)
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
                let identifiers = ingestions.compactMap(\.identifier)
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
            let message = (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn’t delete journal data")
            NotificationCenter.default.post(name: failureNotification, object: message)
            return false
        }
    }

    static func didDelete(identifiers: [UUID]) {
        LeaderboardSyncManager.shared.queueDeletions(identifiers: identifiers)
        Task {
            async let webhooks = WebhookManager.shared.retryPendingDeletions()
            async let leaderboards: Void = LeaderboardSyncManager.shared.retryPendingDeletions()
            if !(await webhooks) {
                NotificationCenter.default.post(name: failureNotification, object: "Webhook cleanup will retry")
            }
            await leaderboards
        }
    }
}
