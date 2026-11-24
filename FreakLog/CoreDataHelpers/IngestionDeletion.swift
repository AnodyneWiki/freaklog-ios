import Foundation

// Deleting ingestions has effects outside CoreData: sent webhook messages are removed and
// leaderboard servers are told about the deletion. Delete ingestions, timed notes and experiences through here.
// The local delete happens right away; the network cleanup runs afterwards in the background.
@MainActor
enum IngestionDeletion {
    static func delete(ingestions: [Ingestion]) async {
        let cleanUp = await remoteCleanUp(for: ingestions)
        let context = PersistenceController.shared.viewContext
        ingestions.filter { !$0.isDeleted }.forEach(context.delete)
        PersistenceController.shared.saveViewContext()
        cleanUp()
    }

    static func delete(timedNote: TimedNote) async {
        let cleanUp = await remoteCleanUp(for: [], timedNotes: [timedNote])
        timedNote.experience?.objectWillChange.send()
        PersistenceController.shared.viewContext.delete(timedNote)
        PersistenceController.shared.saveViewContext()
        cleanUp()
    }

    // The experience's ingestions and timed notes are deleted along with it. Its live activity ends by itself.
    static func delete(experience: Experience) async {
        let cleanUp = await remoteCleanUp(for: experience.ingestionsSorted, timedNotes: experience.timedNotesSorted)
        PersistenceController.shared.viewContext.delete(experience)
        PersistenceController.shared.saveViewContext()
        cleanUp()
    }

    // The unit's ingestions are deleted along with it.
    static func delete(customUnit: CustomUnit) async {
        let cleanUp = await remoteCleanUp(for: customUnit.ingestionsUnwrapped)
        PersistenceController.shared.viewContext.delete(customUnit)
        PersistenceController.shared.saveViewContext()
        cleanUp()
    }

    // Collects what to clean up while the ingestions and timed notes still exist. Call the result once they are deleted.
    static func remoteCleanUp(for ingestions: [Ingestion], timedNotes: [TimedNote] = []) async -> () -> Void {
        let identifiers = ingestions.compactMap(\.identifier)
        let webhookDeletion = await WebhookManager.shared.prepareMessageDeletion(for: ingestions, timedNotes: timedNotes)
        return {
            Task {
                async let webhooks: Void = webhookDeletion.run()
                async let leaderboards: Void = LeaderboardSyncManager.shared.notifyDeletion(identifiers: identifiers)
                _ = await (webhooks, leaderboards)
            }
        }
    }
}
