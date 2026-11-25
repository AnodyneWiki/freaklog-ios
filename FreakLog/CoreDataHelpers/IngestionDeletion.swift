import CoreData

// Deleting ingestions has effects outside CoreData: sent webhook messages are removed and
// leaderboard servers are told about the deletion. Delete ingestions, timed notes and experiences through here.
// The local delete happens right away; the network cleanup runs afterwards in the background.
@MainActor
enum IngestionDeletion {
    @discardableResult
    static func delete(ingestions: [Ingestion]) async -> Bool {
        await delete(ingestions, ingestions: ingestions)
    }

    @discardableResult
    static func delete(timedNote: TimedNote) async -> Bool {
        await delete([timedNote], ingestions: [], timedNotes: [timedNote])
    }

    @discardableResult
    static func delete(experience: Experience) async -> Bool {
        await delete([experience], ingestions: experience.ingestionsSorted, timedNotes: experience.timedNotesSorted)
    }

    @discardableResult
    static func delete(customUnit: CustomUnit) async -> Bool {
        await delete([customUnit], ingestions: customUnit.ingestionsUnwrapped)
    }

    private static func delete(_ objects: [NSManagedObject], ingestions: [Ingestion], timedNotes: [TimedNote] = []) async -> Bool {
        do {
            try PersistenceController.beginJournalOperation()
            defer { PersistenceController.endJournalOperation() }
            let ids = objects.filter { !$0.isDeleted }.map(\.objectID)
            let cleanUp = await remoteCleanUp(for: ingestions, timedNotes: timedNotes)
            try await PersistenceController.shared.container.performBackgroundTask { context in
                for id in ids {
                    context.delete(try context.existingObject(with: id))
                }
                try PersistenceController.saveJournalChanges(in: context)
            }
            cleanUp()
            return true
        } catch {
            print("Journal deletion failed: \(error)")
            return false
        }
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
