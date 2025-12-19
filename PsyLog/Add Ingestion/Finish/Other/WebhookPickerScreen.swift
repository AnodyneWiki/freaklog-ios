import SwiftUI

struct WebhookPickerScreen: View {
    @AppStorage("webhookURL") private var webhookURL = ""
    @AppStorage("webhookName") private var webhookName = ""
    @AppStorage("isWebhookEnabled") private var isWebhookEnabled = false
    @AppStorage("webhookTemplate") private var webhookTemplate = WebhookService.defaultTemplate
    @AppStorage("isSubstanceHyperlinked") private var isSubstanceHyperlinked = false
    @AppStorage("substanceInfoUrl") private var substanceInfoUrl = ""

    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(
                footer: Text("When enabled, a message will be sent to the URL below whenever you finish an ingestion.")
            ) {
                Toggle("Enable Webhook", isOn: $isWebhookEnabled)
                    .tint(.accentColor)
            }

            if isWebhookEnabled {
                Section(
                    header: Text("Configuration"),
                    footer: Text("Paste your Discord webhook URL here.")
                ) {
                    TextField("https://discord.com/api/webhooks/...", text: $webhookURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(
                    header: Text("Links"),
                    footer: Text("If enabled, the substance name becomes a clickable markdown link.")
                ) {
                    Toggle("Hyperlink Substance Name", isOn: $isSubstanceHyperlinked)

                    if isSubstanceHyperlinked {
                        TextField("Base URL", text: $substanceInfoUrl)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section(
                    header: Text("Username"),
                    footer: Text("Used when you are the consumer. If empty, defaults to 'You'.")
                ) {
                    TextField("e.g. Benjamin Engel", text: $webhookName)
                        .keyboardType(.default)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                }

                Section(
                    header: Text("Message Layout"),
                    footer: Text("Wrap text in [ ] to hide it if variables inside are empty.\nVariables: {user}, {dose}, {unit}, {substance}, {route}, {site}, {note}")
                ) {
                    TextEditor(text: $webhookTemplate)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
                    Button("Reset to Default") {
                        webhookTemplate = WebhookService.defaultTemplate
                    }
                    .font(.caption)
                }

                Section {
                    Button("Test Webhook") {
                        Task {
                            await sendTestMessage()
                        }
                    }
                    .disabled(webhookURL.isEmpty)
                }
            }
        }
        .navigationTitle("Webhook Settings")
    }

    private func sendTestMessage() async {
        guard let url = URL(string: webhookURL) else { return }

        let testUser = webhookName.isEmpty ? "You" : webhookName

        var sub = "Caffeine"
        if isSubstanceHyperlinked {
            if let encodedSub = sub.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                sub = "[\(sub)](<\(substanceInfoUrl)\(encodedSub)>)"
            }
        }

        let values: [String: String] = [
            "user": testUser,
            "substance": sub,
            "dose": "~30",
            "unit": "mg",
            "route": "insufflated",
            "site": "left nostril",
            "note": "Test note"
        ]

        let content = WebhookService.processTemplate(webhookTemplate, values: values)
        let payload: [String: Any] = ["content": content]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }
}

#Preview {
    NavigationStack {
        WebhookPickerScreen()
    }
}
