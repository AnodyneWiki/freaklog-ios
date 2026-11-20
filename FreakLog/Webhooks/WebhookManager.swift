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

    func sendWebhooks(
        ingestionObjectID: NSManagedObjectID,
        presetObjectIDs: [NSManagedObjectID],
        dataSnapshot: WebhookDataSnapshot
    ) {
        Task.detached(priority: .background) {
            let container = PersistenceController.shared.container
            let settings = WebhookSettingsSnapshot.current

            struct SendRequest: Sendable {
                let presetObjectID: NSManagedObjectID
                let url: String
            }

            let requests: [SendRequest] = await container.performBackgroundTask { bgContext in
                presetObjectIDs.compactMap { presetID in
                    guard let preset = try? bgContext.existingObject(with: presetID) as? WebhookPreset else { return nil }
                    let url = preset.urlUnwrapped
                    guard !url.isEmpty else { return nil }
                    return SendRequest(presetObjectID: presetID, url: url)
                }
            }

            guard !requests.isEmpty else { return }

            let globalUsername = UserDefaults.standard.string(forKey: PersistenceController.webhookUsernameKey) ?? ""
            let effectiveUser = dataSnapshot.user.isEmpty ? globalUsername : dataSnapshot.user

            for request in requests {
                let result = await WebhookService.sendWebhookWithRetry(
                    url: request.url,
                    user: effectiveUser,
                    substance: dataSnapshot.substance,
                    dose: dataSnapshot.dose,
                    units: dataSnapshot.units,
                    isEstimate: dataSnapshot.isEstimate,
                    route: dataSnapshot.route,
                    site: dataSnapshot.site,
                    note: dataSnapshot.note,
                    template: settings.template,
                    isHyperlinked: settings.isHyperlinked,
                    substanceInfoUrl: settings.substanceInfoUrl,
                    isEdit: false,
                    messageId: nil
                )

                if let messageId = result.messageId, result.success {
                    await container.performBackgroundTask { bgContext in
                        guard
                            let bgPreset = try? bgContext.existingObject(with: request.presetObjectID) as? WebhookPreset,
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

    // MARK: - Editing Webhooks

    func editWebhookMessages(for ingestion: Ingestion) async {
        let ingestionObjectID = ingestion.objectID
        let context = PersistenceController.shared.viewContext

        let effectiveUserName = ingestion.consumerNameUnwrapped.isEmpty ? "" : ingestion.consumerNameUnwrapped
        let substanceName = ingestion.substanceNameUnwrapped
        let dose = ingestion.doseUnwrapped ?? 0
        let isEstimate = ingestion.isEstimate
        let route = ingestion.administrationRouteUnwrapped.rawValue
        let site = ingestion.administrationSiteUnwrapped
        let note = ingestion.noteUnwrapped

        let units: String
        if let customUnit = ingestion.customUnit {
            units = dose.justUnit(pluralizableUnit: customUnit.pluralizableUnit)
        } else {
            units = ingestion.unitsUnwrapped
        }

        struct MessageInfo: Sendable {
            let presetObjectID: NSManagedObjectID
            let messageId: String
        }

        var messageInfos: [MessageInfo] = []

        context.performAndWait {
            if let ingestionInContext = context.object(with: ingestionObjectID) as? Ingestion {
                let messages = ingestionInContext.webhookMessagesSorted
                messageInfos = messages.compactMap { message in
                    guard let preset = message.webhookPreset,
                          let messageId = message.messageId else { return nil }
                    return MessageInfo(presetObjectID: preset.objectID, messageId: messageId)
                }
            }
        }

        guard !messageInfos.isEmpty else { return }

        Task.detached(priority: .background) {
            let container = PersistenceController.shared.container
            let settings = WebhookSettingsSnapshot.current

            let requests: [(url: String, messageId: String)] = await container.performBackgroundTask { bgContext in
                messageInfos.compactMap { info in
                    guard let preset = try? bgContext.existingObject(with: info.presetObjectID) as? WebhookPreset else {
                        return nil
                    }
                    let url = preset.urlUnwrapped
                    guard !url.isEmpty else { return nil }
                    return (url: url, messageId: info.messageId)
                }
            }

            let globalUsername = UserDefaults.standard.string(forKey: PersistenceController.webhookUsernameKey) ?? ""
            let effectiveUser = effectiveUserName.isEmpty ? globalUsername : effectiveUserName

            for request in requests {
                _ = await WebhookService.sendWebhookWithRetry(
                    url: request.url,
                    user: effectiveUser,
                    substance: substanceName,
                    dose: dose,
                    units: units,
                    isEstimate: isEstimate,
                    route: route,
                    site: site,
                    note: note,
                    template: settings.template,
                    isHyperlinked: settings.isHyperlinked,
                    substanceInfoUrl: settings.substanceInfoUrl,
                    isEdit: true,
                    messageId: request.messageId
                )
            }
        }
    }

    // MARK: - Deleting Webhooks

    private struct DeletionTarget: Sendable {
        let messageObjectID: NSManagedObjectID
        let url: String
        let messageId: String
    }

    private func executeDeletions(_ targets: [DeletionTarget], in container: NSPersistentContainer, also extraObjectID: NSManagedObjectID? = nil) async {
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
        await deleteWebhookMessages(forIngestionObjectIDs: ingestions.map { $0.objectID })
    }

    func deleteWebhookMessages(forIngestionObjectIDs ingestionObjectIDs: [NSManagedObjectID]) async {
        guard !ingestionObjectIDs.isEmpty else { return }
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
        await executeDeletions(targets, in: container)
    }

    func deleteMessages(for preset: WebhookPreset) async {
        let container = PersistenceController.shared.container
        let targets = await buildPresetDeletionTargets(presetID: preset.objectID, in: container)
        await executeDeletions(targets, in: container)
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
