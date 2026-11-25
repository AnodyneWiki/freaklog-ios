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
        guard let context = ingestions.first?.managedObjectContext else { return }
        try PersistenceController.saveJournalChanges(in: context)
        didSave(ingestions, newIngestions: newIngestions, sendingWebhooksTo: presetObjectIDs)
    }

    static func didSave(_ ingestions: [Ingestion], newIngestions: [Ingestion], sendingWebhooksTo presetObjectIDs: [NSManagedObjectID] = []) {
        let confirmed = ingestions.filter { !$0.isUnconfirmed }
        guard !confirmed.isEmpty else { return }
        for ingestion in confirmed {
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
        if confirmed.contains(where: { $0.routineOccurrence != nil }) {
            Task { await RoutineSchedules.shared.refresh() }
        }
    }

    static func stageConfirmation(
        for ingestion: Ingestion,
        stockContainerID: NSManagedObjectID?,
        in context: NSManagedObjectContext
    ) throws -> [Ingestion] {
        let pending = ingestion.pendingConfirmationEntries
        guard !pending.isEmpty else { throw ConfirmationError.alreadyConfirmed }
        let pendingSet = Set(pending)
        for occurrence in Set(pending.compactMap(\.routineOccurrence)) {
            let linked = occurrence.ingestions?.allObjects as? [Ingestion] ?? []
            guard !occurrence.isSkipped, !linked.contains(where: { !pendingSet.contains($0) && !$0.isUnconfirmed }) else {
                throw ConfirmationError.routineChanged
            }
            occurrence.snoozedUntil = nil
        }
        if let stockContainerID {
            guard let use = Inventory.Use(pending.map(\.inventoryArguments)) else { throw InventoryError.sourceChanged }
            try use.stage(using: stockContainerID, for: pending, at: ingestion.timeUnwrapped, in: context)
        }
        for entry in pending {
            entry.isUnconfirmed = false
            entry.confirmationBatchID = nil
        }
        return pending
    }

    private enum ConfirmationError: LocalizedError {
        case alreadyConfirmed
        case routineChanged

        var errorDescription: String? {
            switch self {
            case .alreadyConfirmed: String(localized: "This ingestion has already been confirmed.")
            case .routineChanged: String(localized: "The linked routine was skipped or already logged.")
            }
        }
    }
}

// Timed notes are sent to webhooks like ingestions: a new one to the chosen presets, an edited one updates
// the messages already sent for it. Save added and edited timed notes through here.
@MainActor
enum TimedNoteSaving {
    static func save(_ timedNote: TimedNote, sendingWebhooksTo presetObjectIDs: [NSManagedObjectID] = []) throws {
        let isNew = timedNote.isInserted
        let isNoteChanged = timedNote.changedValues().keys.contains("note")
        guard let context = timedNote.managedObjectContext else { return }
        try PersistenceController.saveJournalChanges(in: context)
        if isNew {
            WebhookManager.shared.sendWebhooks(for: timedNote, presetObjectIDs: presetObjectIDs)
        } else if isNoteChanged {
            WebhookManager.shared.editWebhookMessages(for: timedNote)
        }
    }
}

extension WebhookPreset {
    // What adding sends to unless chosen otherwise: every enabled preset, if sending is turned on
    @MainActor
    static func defaultPresetObjectIDs() -> [NSManagedObjectID] {
        guard UserDefaults.standard.bool(forKey: PersistenceController.sendWebhooksEnabledKey) else { return [] }
        let context = PersistenceController.shared.viewContext
        return ((try? context.fetch(PersistenceController.enabledWebhookPresetsRequest())) ?? []).map(\.objectID)
    }
}
