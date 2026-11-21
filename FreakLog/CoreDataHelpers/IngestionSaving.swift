import CoreData

// Saving an ingestion has effects outside CoreData: a new one is sent to the chosen webhooks, an edited one
// updates the webhook messages already sent for it, and either way leaderboard servers are synced.
// Save added and edited ingestions through here. The live activity follows the saved data by itself.
@MainActor
enum IngestionSaving {
    static func save(_ ingestion: Ingestion, sendingWebhooksTo presetObjectIDs: [NSManagedObjectID] = []) throws {
        let isNew = ingestion.isInserted
        try PersistenceController.shared.viewContext.save()
        if isNew {
            if !presetObjectIDs.isEmpty {
                WebhookManager.shared.sendWebhooks(for: ingestion, presetObjectIDs: presetObjectIDs)
            }
        } else {
            WebhookManager.shared.editWebhookMessages(for: ingestion)
        }
        Task {
            await LeaderboardSyncManager.shared.syncAll()
        }
    }
}
