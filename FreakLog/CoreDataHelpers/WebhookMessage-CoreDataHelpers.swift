import Foundation

extension WebhookMessage {
    var presetNameUnwrapped: String {
        webhookPreset?.name ?? "Unknown Webhook"
    }
}
