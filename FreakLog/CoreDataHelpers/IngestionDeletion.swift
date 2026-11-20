import Foundation

// Deleting ingestions has effects outside CoreData: sent webhook messages are removed and
// leaderboard servers are told about the deletion. Delete ingestions and experiences through here.
@MainActor
enum IngestionDeletion {
    static func delete(ingestions: [Ingestion]) async {
        await cleanUpRemoteData(for: ingestions)
        let context = PersistenceController.shared.viewContext
        ingestions.filter { !$0.isDeleted }.forEach(context.delete)
        PersistenceController.shared.saveViewContext()
    }

    // The experience's ingestions are deleted along with it.
    static func delete(experience: Experience) async {
        await cleanUpRemoteData(for: experience.ingestionsSorted)
        PersistenceController.shared.viewContext.delete(experience)
        PersistenceController.shared.saveViewContext()
    }

    private static func cleanUpRemoteData(for ingestions: [Ingestion]) async {
        let identifiers = ingestions.compactMap(\.identifier)
        await WebhookManager.shared.deleteWebhookMessages(for: ingestions)
        for identifier in identifiers {
            await LeaderboardSyncManager.shared.notifyDeletion(identifier: identifier)
        }
    }
}
