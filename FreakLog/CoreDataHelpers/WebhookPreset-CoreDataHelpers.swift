import CoreData
import Foundation

extension WebhookPreset {
    var idUnwrapped: UUID {
        id ?? UUID()
    }

    var nameUnwrapped: String {
        name ?? "Unnamed Webhook"
    }

    var displayName: String {
        nameUnwrapped.isEmpty ? "Unnamed" : nameUnwrapped
    }

    var urlUnwrapped: String {
        url ?? ""
    }

    var canEditURL: Bool {
        urlUnwrapped.isEmpty
    }

    static func new(in context: NSManagedObjectContext) -> WebhookPreset {
        let preset = WebhookPreset(context: context)
        preset.id = UUID()
        preset.creationDate = Date()
        preset.isEnabled = true
        preset.name = ""
        return preset
    }
}
