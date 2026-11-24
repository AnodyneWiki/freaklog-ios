import CoreData

// Saving an ingestion has effects outside CoreData: a new one is sent to the chosen webhooks, an edited one
// updates the webhook messages already sent for it, and either way leaderboard servers are synced.
// Save added and edited ingestions through here. The live activity follows the saved data by itself.
@MainActor
enum IngestionSaving {
    static func save(_ ingestion: Ingestion, sendingWebhooksTo presetObjectIDs: [NSManagedObjectID] = []) throws {
        try save([ingestion], sendingWebhooksTo: presetObjectIDs)
    }

    // Several ingestions logged together, like the substances of a formulation, are saved at once
    // and each gets its own webhook message
    static func save(_ ingestions: [Ingestion], sendingWebhooksTo presetObjectIDs: [NSManagedObjectID] = []) throws {
        let newIngestions = ingestions.filter(\.isInserted)
        try PersistenceController.shared.viewContext.save()
        for ingestion in ingestions {
            if newIngestions.contains(ingestion) {
                if !presetObjectIDs.isEmpty {
                    WebhookManager.shared.sendWebhooks(for: ingestion, presetObjectIDs: presetObjectIDs)
                }
            } else {
                WebhookManager.shared.editWebhookMessages(for: ingestion)
            }
        }
        Task {
            await LeaderboardSyncManager.shared.syncAll()
        }
    }
}
