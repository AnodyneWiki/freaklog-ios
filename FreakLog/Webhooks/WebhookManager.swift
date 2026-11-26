import Foundation
import CoreData
import OSLog
import os

@MainActor
final class WebhookManager {
    static let shared = WebhookManager(container: PersistenceController.shared.container)
    nonisolated static let failureNotification = Notification.Name("WebhookOperationDidFail")

    typealias SendMessage = (String, String, String?) async -> WebhookResult
    typealias DeleteMessage = (String, String) async -> Bool

    private let container: NSPersistentContainer
    private let sendMessage: SendMessage
    private let deleteMessageFromServer: DeleteMessage
    private let reportFailure: (String) -> Void
    private var initialSends: [UUID: InitialSend] = [:]
    private var pendingEdits: [Destination: String] = [:]
    private var editTasks: [Destination: Task<Void, Never>] = [:]
    private var deletionTasks: [Destination: Task<Bool, Never>] = [:]
    private var unsavedDeletions: Set<Destination> = []

    init(
        container: NSPersistentContainer,
        sendMessage: @escaping SendMessage = WebhookService.sendWebhookWithRetry,
        deleteMessage: @escaping DeleteMessage = WebhookService.deleteWebhookMessage,
        reportFailure: @escaping (String) -> Void = { message in
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "FreakLog", category: "Webhook").error("\(message, privacy: .public)")
            NotificationCenter.default.post(name: failureNotification, object: message)
        }
    ) {
        self.container = container
        self.sendMessage = sendMessage
        deleteMessageFromServer = deleteMessage
        self.reportFailure = reportFailure
    }

    struct WebhookDataSnapshot: Sendable {
        let user: String
        let substance: String
        // Shown in the message; `substance` is the stored name, used for the info link
        let substanceDisplayName: String
        let dose: Double
        let units: String
        let isEstimate: Bool
        let route: String
        let site: String
        let simpleSite: String
        let note: String
    }

    struct WebhookSettingsSnapshot: Sendable {
        let template: String
        let noteTemplate: String
        let username: String
        let isHyperlinked: Bool
        let substanceInfoUrl: String

        static var current: WebhookSettingsSnapshot {
            let defaults = UserDefaults.standard
            return WebhookSettingsSnapshot(
                template: defaults.string(forKey: PersistenceController.webhookTemplateKey) ?? WebhookService.defaultTemplate,
                noteTemplate: defaults.string(forKey: PersistenceController.webhookNoteTemplateKey) ?? WebhookService.defaultNoteTemplate,
                username: defaults.string(forKey: PersistenceController.webhookUsernameKey) ?? "",
                isHyperlinked: defaults.bool(forKey: PersistenceController.webhookIsHyperlinkedKey),
                substanceInfoUrl: defaults.string(forKey: PersistenceController.webhookSubstanceInfoUrlKey) ?? ""
            )
        }
    }

    private struct InitialSend {
        let ownerID: NSManagedObjectID
        let presetID: NSManagedObjectID
        let url: String
        var content: String
        let keepRemoteMessage = OSAllocatedUnfairLock(initialState: false)
    }

    private enum TrackingOutcome {
        case tracked
        case missingOwnerOrPreset
        case keepRemoteMessage
    }

    struct Destination: Hashable, Sendable {
        let url: String
        let messageId: String

        init?(url: String?, messageId: String?) {
            guard let url, !url.isEmpty, let messageId, !messageId.isEmpty else { return nil }
            self.url = url
            self.messageId = messageId
        }

        init?(_ message: WebhookMessage) {
            self.init(url: message.destinationURL ?? message.webhookPreset?.url, messageId: message.messageId)
        }

        func stage(in context: NSManagedObjectContext) {
            let deletion = WebhookDeletion(context: context)
            deletion.url = url
            deletion.messageId = messageId
        }

        var deletionRequest: NSFetchRequest<WebhookDeletion> {
            let request = WebhookDeletion.fetchRequest()
            request.predicate = NSPredicate(format: "url == %@ AND messageId == %@", url, messageId)
            return request
        }
    }

    // MARK: - Sending Webhooks

    func sendWebhooks(for ingestion: Ingestion, presetObjectIDs: [NSManagedObjectID]) {
        let content = WebhookService.content(for: WebhookDataSnapshot(ingestion: ingestion), settings: .current)
        send(content, about: ingestion.objectID, to: presetObjectIDs)
    }

    func sendWebhooks(for timedNote: TimedNote, presetObjectIDs: [NSManagedObjectID]) {
        let content = WebhookService.content(forNote: timedNote.noteUnwrapped, settings: .current)
        send(content, about: timedNote.objectID, to: presetObjectIDs)
    }

    private func send(_ content: String, about ownerID: NSManagedObjectID, to presetIDs: [NSManagedObjectID]) {
        guard !presetIDs.isEmpty else { return }
        let context = container.viewContext
        for presetID in Set(presetIDs) {
            guard let preset = try? context.existingObject(with: presetID) as? WebhookPreset,
                  !preset.isDeleted, let url = preset.url, !url.isEmpty else { continue }
            let id = UUID()
            initialSends[id] = InitialSend(ownerID: ownerID, presetID: presetID, url: url, content: content)
            Task { await completeInitialSend(id) }
        }
    }

    private func completeInitialSend(_ id: UUID) async {
        guard let initial = initialSends[id] else { return }
        defer { initialSends.removeValue(forKey: id) }
        let canSend = withStore { context in
            !initial.keepRemoteMessage.withLock { $0 } && Self.deliveryObjects(for: initial, in: context) != nil
        }
        guard canSend else { return }

        let result = await sendMessage(initial.url, initial.content, nil)
        guard result.success, let target = Destination(url: initial.url, messageId: result.messageId) else {
            if result.error as? WebhookService.DeliveryError == .unknownDelivery || result.success {
                reportFailure("Couldn't confirm webhook delivery. Check the destination for the message.")
            } else {
                reportFailure("Couldn't send a webhook message.")
            }
            return
        }

        do {
            let outcome: TrackingOutcome = try withStore { context in
                if initial.keepRemoteMessage.withLock({ $0 }) { return .keepRemoteMessage }
                guard let (owner, preset) = Self.deliveryObjects(for: initial, in: context) else { return .missingOwnerOrPreset }
                let message = WebhookMessage(context: context)
                message.id = id
                message.creationDate = Date()
                message.messageId = target.messageId
                message.destinationURL = target.url
                message.ingestion = owner as? Ingestion
                message.timedNote = owner as? TimedNote
                message.webhookPreset = preset
                try context.save()
                return .tracked
            }
            switch outcome {
            case .tracked:
                if let latest = initialSends[id]?.content, latest != initial.content { enqueueEdit(of: target, to: latest) }
                return
            case .keepRemoteMessage:
                return
            case .missingOwnerOrPreset:
                break
            }
        } catch {
            reportFailure("Couldn't save webhook message tracking. The message will be removed.")
        }

        // The owner or preset may disappear while POST is in flight. If the tracking save
        // fails, retain the delivery as a cleanup target before trying the remote delete.
        unsavedDeletions.insert(target)
        if !(await retryPendingDeletions()) {
            reportFailure("Some webhook messages couldn't be removed. Cleanup will be retried.")
        }
    }

    nonisolated private static func deliveryObjects(
        for initial: InitialSend,
        in context: NSManagedObjectContext
    ) -> (NSManagedObject, WebhookPreset)? {
        guard let owner = try? context.existingObject(with: initial.ownerID),
              let preset = try? context.existingObject(with: initial.presetID) as? WebhookPreset else { return nil }
        return (owner, preset)
    }

    // MARK: - Editing Webhooks

    func editWebhookMessages(for ingestion: Ingestion) {
        let content = WebhookService.content(for: WebhookDataSnapshot(ingestion: ingestion), settings: .current)
        edit(about: ingestion.objectID, to: content)
    }

    func editWebhookMessages(for timedNote: TimedNote) {
        let content = WebhookService.content(forNote: timedNote.noteUnwrapped, settings: .current)
        edit(about: timedNote.objectID, to: content)
    }

    private func edit(about ownerID: NSManagedObjectID, to content: String) {
        for id in initialSends.keys where initialSends[id]?.ownerID == ownerID {
            initialSends[id]?.content = content
        }
        // Read the store directly so we can see tracking even before the UI context merges it.
        let targets: Set<Destination> = withStore { context in
            guard let owner = try? context.existingObject(with: ownerID) else { return [] }
            let messages = (owner as? Ingestion)?.webhookMessagesSorted ?? (owner as? TimedNote)?.webhookMessagesSorted ?? []
            return Set(messages.compactMap(Destination.init))
        }
        for target in targets {
            enqueueEdit(of: target, to: content)
        }
    }

    private func enqueueEdit(of target: Destination, to content: String) {
        guard deletionTasks[target] == nil else { return }
        pendingEdits[target] = content
        guard editTasks[target] == nil else { return }
        editTasks[target] = Task {
            while let content = pendingEdits.removeValue(forKey: target) {
                let result = await sendMessage(target.url, content, target.messageId)
                if !result.success, pendingEdits[target] == nil, deletionTasks[target] == nil {
                    reportFailure("Couldn't update a webhook message.")
                }
            }
            editTasks.removeValue(forKey: target)
        }
    }

    // MARK: - Deleting Webhooks

    // Insert retry records in the same transaction as the local deletion so rollback
    // preserves the remote messages, and cascades cannot remove the retry records.
    nonisolated static func stageMessageDeletion(
        for ingestions: [Ingestion],
        timedNotes: [TimedNote] = [],
        in context: NSManagedObjectContext
    ) {
        let messages = ingestions.flatMap(\.webhookMessagesSorted) + timedNotes.flatMap(\.webhookMessagesSorted)
        stageDeletion(of: messages, in: context)
    }

    nonisolated static func stageAllPresetDeletion(in context: NSManagedObjectContext) throws {
        let presets = try context.fetch(WebhookPreset.fetchRequest())
        stageDeletion(of: presets.flatMap { $0.messages?.allObjects as? [WebhookMessage] ?? [] }, in: context)
        presets.forEach(context.delete)
    }

    nonisolated private static func stageDeletion(of messages: [WebhookMessage], in context: NSManagedObjectContext) {
        let queued = Set(context.insertedObjects.compactMap { object -> Destination? in
            guard let deletion = object as? WebhookDeletion else { return nil }
            return Destination(url: deletion.url, messageId: deletion.messageId)
        })
        for destination in Set(messages.compactMap(Destination.init)).subtracting(queued) {
            destination.stage(in: context)
        }
    }

    @discardableResult
    func retryPendingDeletions() async -> Bool {
        let targets: Set<Destination>
        let loadedQueue: Bool
        let unpersistedTargets = unsavedDeletions
        do {
            targets = try withStore { context in
                for target in unpersistedTargets {
                    target.stage(in: context)
                }
                if context.hasChanges { try context.save() }
                return Set(try context.fetch(WebhookDeletion.fetchRequest()).compactMap {
                    Destination(url: $0.url, messageId: $0.messageId)
                })
            }
            unsavedDeletions.removeAll()
            loadedQueue = true
        } catch {
            // A late ID still permits a best-effort delete while local storage is unavailable.
            targets = unsavedDeletions
            loadedQueue = false
        }
        return await withTaskGroup(of: Bool.self) { group in
            for target in targets {
                group.addTask { await self.completeDeletion(of: target) }
            }
            var allDeleted = loadedQueue
            for await deleted in group {
                allDeleted = allDeleted && deleted
            }
            return allDeleted
        }
    }

    private func completeDeletion(of target: Destination) async -> Bool {
        guard await deleteRemotely(target) else { return false }
        unsavedDeletions.remove(target)
        do {
            try withStore { context in
                try context.fetch(target.deletionRequest).forEach(context.delete)
                if context.hasChanges { try context.save() }
            }
            return true
        } catch {
            return false
        }
    }

    private func deleteRemotely(_ target: Destination) async -> Bool {
        if let inFlight = deletionTasks[target] { return await inFlight.value }

        pendingEdits.removeValue(forKey: target)
        let currentEdit = editTasks[target]
        let deletion = Task {
            await currentEdit?.value
            return await deleteMessageFromServer(target.url, target.messageId)
        }
        deletionTasks[target] = deletion
        let deleted = await deletion.value
        deletionTasks.removeValue(forKey: target)
        return deleted
    }

    // Keep the visible tracking row when the user asks to delete just one message and the request fails.
    func deleteMessage(_ message: WebhookMessage) async -> Bool {
        guard let target = Destination(message), await deleteRemotely(target) else { return false }
        let id = message.objectID
        do {
            try withStore { context in
                guard let stored = try? context.existingObject(with: id) else { return }
                context.delete(stored)
                try context.save()
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func deletePreset(_ preset: WebhookPreset, deletingMessages: Bool) async throws -> Bool {
        let presetID = preset.objectID
        try withStore { context in
            guard let stored = try? context.existingObject(with: presetID) as? WebhookPreset else { return }
            if deletingMessages {
                Self.stageDeletion(of: stored.messages?.allObjects as? [WebhookMessage] ?? [], in: context)
            }
            context.delete(stored)
            try context.save()
        }
        if deletingMessages { return await retryPendingDeletions() }

        for initial in initialSends.values where initial.presetID == presetID {
            initial.keepRemoteMessage.withLock { $0 = true }
        }
        return true
    }

    // Call the returned closure within the replacement transaction after it commits.
    func makeInFlightRetentionCommit() -> @Sendable () -> Void {
        let pending = initialSends.values.map(\.keepRemoteMessage)
        return {
            for flag in pending {
                flag.withLock { $0 = true }
            }
        }
    }

    // Transactions are synchronous on the main actor with journal deletion staging, while
    // using an independent context so unrelated unsaved form changes cannot join them.
    private func withStore<Value>(_ work: (NSManagedObjectContext) throws -> Value) rethrows -> Value {
        let context = container.newBackgroundContext()
        return try context.performAndWait {
            try PersistenceController.withJournalStoreWrite { try work(context) }
        }
    }
}

extension WebhookManager.WebhookDataSnapshot {
    // The message for a saved ingestion, used both when sending and when editing it
    init(ingestion: Ingestion) {
        let dose = ingestion.doseUnwrapped ?? 0
        let route = ingestion.administrationRouteUnwrapped
        let site = ingestion.administrationSiteUnwrapped
        self.init(
            user: ingestion.isMine ? "" : ingestion.consumerNameUnwrapped,
            substance: ingestion.substanceNameUnwrapped,
            substanceDisplayName: ingestion.substanceDisplayName,
            dose: dose,
            units: ingestion.customUnit.map { dose.justUnit(pluralizableUnit: $0.pluralizableUnit) } ?? ingestion.unitsUnwrapped,
            isEstimate: ingestion.isEstimate,
            route: route.rawValue,
            site: site.lowercased(),
            simpleSite: AdministrationSiteNameStyle.simple.label(for: site, route: route).lowercased(),
            note: ingestion.noteUnwrapped
        )
    }
}
