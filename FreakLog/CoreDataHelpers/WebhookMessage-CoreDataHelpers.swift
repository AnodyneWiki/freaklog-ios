import Foundation

extension WebhookMessage {
    var messageIdUnwrapped: String {
        messageId ?? ""
    }

    var presetNameUnwrapped: String {
        webhookPreset?.name ?? "Unknown Webhook"
    }
}
