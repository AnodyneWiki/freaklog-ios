import Foundation
import CoreData

final class WebhookManager: Sendable {
    static let shared = WebhookManager()

    private init() {}

    struct WebhookDataSnapshot: Sendable {
        let user: String
        let substance: String
        let dose: Double
        let units: String
        let isEstimate: Bool
        let route: String
        let site: String
        let note: String
    }

    struct WebhookSettingsSnapshot: Sendable {
        let template: String
        let isHyperlinked: Bool
        let substanceInfoUrl: String

        static var current: WebhookSettingsSnapshot {
            WebhookSettingsSnapshot(
                template: UserDefaults.standard.string(forKey: PersistenceController.webhookTemplateKey) ?? WebhookService.defaultTemplate,
                isHyperlinked: UserDefaults.standard.bool(forKey: PersistenceController.webhookIsHyperlinkedKey),
                substanceInfoUrl: UserDefaults.standard.string(forKey: PersistenceController.webhookSubstanceInfoUrlKey) ?? ""
            )
        }
    }

    // MARK: - Sending Webhooks

    func sendWebhooks(for ingestion: Ingestion, presetObjectIDs: [NSManagedObjectID]) {
        let ingestionObjectID = ingestion.objectID
        let data = WebhookDataSnapshot(ingestion: ingestion)
        Task.detached(priority: .background) {
            let container = PersistenceController.shared.container
            let urls = await Self.urls(of: presetObjectIDs, in: container)
            await withTaskGroup(of: Void.self) { group in
                for (presetObjectID, url) in urls {
                    group.addTask {
                        let result = await WebhookService.sendWebhookWithRetry(url: url, data: data, settings: .current)
                        guard result.success, let messageId = result.messageId else { return }
                        await container.performBackgroundTask { bgContext in
                            guard
                                let bgPreset = try? bgContext.existingObject(with: presetObjectID) as? WebhookPreset,
                                let bgIngestion = try? bgContext.existingObject(with: ingestionObjectID) as? Ingestion
                            else { return }

                            let message = WebhookMessage(context: bgContext)
                            message.id = UUID()
                            message.creationDate = Date()
                            message.messageId = messageId
                            message.ingestion = bgIngestion
                            message.webhookPreset = bgPreset
                            try? bgContext.save()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Editing Webhooks

    func editWebhookMessages(for ingestion: Ingestion) {
        let data = WebhookDataSnapshot(ingestion: ingestion)
        let messages = ingestion.webhookMessagesSorted.compactMap { message -> (preset: NSManagedObjectID, id: String)? in
            guard let preset = message.webhookPreset, let messageId = message.messageId else { return nil }
            return (preset.objectID, messageId)
        }
        guard !messages.isEmpty else { return }

        Task.detached(priority: .background) {
            let container = PersistenceController.shared.container
            let urls = await Self.urls(of: messages.map(\.preset), in: container)
            await withTaskGroup(of: Void.self) { group in
                for message in messages {
                    guard let url = urls.first(where: { $0.presetObjectID == message.preset })?.url else { continue }
                    group.addTask {
                        _ = await WebhookService.sendWebhookWithRetry(
                            url: url,
                            data: data,
                            settings: .current,
                            editing: message.id
                        )
                    }
                }
            }
        }
    }

    // Presets that still exist and have a URL
    private static func urls(
        of presetObjectIDs: [NSManagedObjectID],
        in container: NSPersistentContainer
    ) async -> [(presetObjectID: NSManagedObjectID, url: String)] {
        await container.performBackgroundTask { bgContext in
            presetObjectIDs.compactMap { presetID in
                guard let preset = try? bgContext.existingObject(with: presetID) as? WebhookPreset else { return nil }
                let url = preset.urlUnwrapped
                return url.isEmpty ? nil : (presetID, url)
            }
        }
    }

    // MARK: - Deleting Webhooks

    fileprivate struct DeletionTarget: Sendable {
        let messageObjectID: NSManagedObjectID
        let url: String
        let messageId: String
    }

    // Messages to delete, collected before their ingestions are deleted locally
    struct PendingMessageDeletion: Sendable {
        fileprivate let targets: [DeletionTarget]

        func run() async {
            await WebhookManager.shared.executeDeletions(targets, in: PersistenceController.shared.container)
        }
    }

    fileprivate func executeDeletions(
        _ targets: [DeletionTarget],
        in container: NSPersistentContainer,
        also extraObjectID: NSManagedObjectID? = nil
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask {
                    _ = await WebhookService.deleteWebhookMessage(url: target.url, messageId: target.messageId)
                }
            }
        }
        await container.performBackgroundTask { bgContext in
            for target in targets {
                if let msg = try? bgContext.existingObject(with: target.messageObjectID) as? WebhookMessage {
                    bgContext.delete(msg)
                }
            }
            if let id = extraObjectID, let obj = try? bgContext.existingObject(with: id) {
                bgContext.delete(obj)
            }
            try? bgContext.save()
        }
    }

    private func buildPresetDeletionTargets(presetID: NSManagedObjectID, in container: NSPersistentContainer) async -> [DeletionTarget] {
        await container.performBackgroundTask { bgContext in
            guard let bgPreset = try? bgContext.existingObject(with: presetID) as? WebhookPreset else { return [] }
            let url = bgPreset.urlUnwrapped
            guard !url.isEmpty else { return [] }
            return (bgPreset.messages?.allObjects as? [WebhookMessage] ?? []).compactMap { msg in
                guard let messageId = msg.messageId else { return nil }
                return DeletionTarget(messageObjectID: msg.objectID, url: url, messageId: messageId)
            }
        }
    }

    func deleteWebhookMessages(for ingestions: [Ingestion]) async {
        await prepareMessageDeletion(for: ingestions).run()
    }

    func prepareMessageDeletion(for ingestions: [Ingestion]) async -> PendingMessageDeletion {
        let ingestionObjectIDs = ingestions.map(\.objectID)
        guard !ingestionObjectIDs.isEmpty else { return PendingMessageDeletion(targets: []) }
        let container = PersistenceController.shared.container
        let targets: [DeletionTarget] = await container.performBackgroundTask { bgContext in
            ingestionObjectIDs.flatMap { ingestionID -> [DeletionTarget] in
                guard let ingestion = try? bgContext.existingObject(with: ingestionID) as? Ingestion else { return [] }
                return ingestion.webhookMessagesSorted.compactMap { message in
                    guard let preset = message.webhookPreset,
                          let messageId = message.messageId,
                          let url = preset.url, !url.isEmpty
                    else { return nil }
                    return DeletionTarget(messageObjectID: message.objectID, url: url, messageId: messageId)
                }
            }
        }
        return PendingMessageDeletion(targets: targets)
    }

    // Deletes one sent message remotely and, only if that worked, locally
    @MainActor
    func deleteMessage(_ message: WebhookMessage) async -> Bool {
        guard let url = message.webhookPreset?.url, !url.isEmpty, let messageId = message.messageId else { return false }
        guard await WebhookService.deleteWebhookMessage(url: url, messageId: messageId) else { return false }
        message.managedObjectContext?.delete(message)
        PersistenceController.shared.saveViewContext()
        return true
    }

    @MainActor
    func deletePreset(_ preset: WebhookPreset, deletingMessages: Bool) async {
        if deletingMessages {
            await deleteMessagesAndPreset(presetID: preset.objectID)
        } else {
            preset.managedObjectContext?.delete(preset)
            PersistenceController.shared.saveViewContext()
        }
    }

    func deleteAllPresetsAndMessages() async {
        let container = PersistenceController.shared.container
        let presetObjectIDs: [NSManagedObjectID] = await container.performBackgroundTask { bgContext in
            let fetchRequest = WebhookPreset.fetchRequest()
            return (try? bgContext.fetch(fetchRequest).map { $0.objectID }) ?? []
        }
        await withTaskGroup(of: Void.self) { group in
            for presetID in presetObjectIDs {
                group.addTask {
                    await self.deleteMessagesAndPreset(presetID: presetID)
                }
            }
        }
    }

    private func deleteMessagesAndPreset(presetID: NSManagedObjectID) async {
        let container = PersistenceController.shared.container
        let targets = await buildPresetDeletionTargets(presetID: presetID, in: container)
        await executeDeletions(targets, in: container, also: presetID)
    }
}

extension WebhookManager.WebhookDataSnapshot {
    // The message for a saved ingestion, used both when sending and when editing it
    init(ingestion: Ingestion) {
        let dose = ingestion.doseUnwrapped ?? 0
        self.init(
            user: ingestion.isMine ? "" : ingestion.consumerNameUnwrapped,
            substance: ingestion.substanceNameUnwrapped,
            dose: dose,
            units: ingestion.customUnit.map { dose.justUnit(pluralizableUnit: $0.pluralizableUnit) } ?? ingestion.unitsUnwrapped,
            isEstimate: ingestion.isEstimate,
            route: ingestion.administrationRouteUnwrapped.rawValue,
            site: ingestion.administrationSiteUnwrapped.lowercased(),
            note: ingestion.noteUnwrapped
        )
    }
}
