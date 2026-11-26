import SwiftUI
import CoreData

struct EditWebhookPresetScreen: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastViewModel: ToastViewModel

    private let presetToEdit: WebhookPreset?
    private let onSaveNew: ((WebhookPreset) -> Void)?
    private let onCancelNew: (() -> Void)?

    @State private var presetName: String = ""
    @State private var presetURL: String = ""
    @State private var isEnabled: Bool = true

    @State private var hasInitialized: Bool = false

    init(preset: WebhookPreset) {
        self.presetToEdit = preset
        self.onSaveNew = nil
        self.onCancelNew = nil
    }

    init(isNewPreset: Bool, onSave: @escaping (WebhookPreset) -> Void, onCancel: @escaping () -> Void) {
        self.presetToEdit = nil
        self.onSaveNew = onSave
        self.onCancelNew = onCancel
    }

    private var isNewPreset: Bool {
        presetToEdit == nil
    }

    private var canEditURL: Bool {
        if isNewPreset {
            return true
        } else {
            return presetToEdit?.urlUnwrapped.isEmpty ?? true
        }
    }

    var body: some View {
        Form {
            Section(header: Text("General")) {
                TextField("Preset Name (e.g. My Server)", text: $presetName)

                Toggle("Enabled", isOn: $isEnabled)
            }

            Section(
                header: Text("Configuration"),
                footer: Text(canEditURL ? "Paste your Discord webhook URL here. This cannot be changed after saving." : "The Webhook URL cannot be changed after saving.")
            ) {
                if canEditURL {
                    TextField("https://discord.com/api/webhooks/...", text: $presetURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    Text(presetURL)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button("Test Webhook") {
                    Task {
                        await sendTestMessage()
                    }
                }
                .disabled(presetURL.isEmpty)
            }
        }
        .navigationTitle(isNewPreset ? "New Webhook" : (presetName.isEmpty ? "New Webhook" : presetName))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isNewPreset {
                        onCancelNew?()
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveAndDismiss()
                }
                .disabled(presetName.isEmpty || presetURL.isEmpty)
            }
        }
        .onAppear {
            if !hasInitialized, let preset = presetToEdit {
                presetName = preset.nameUnwrapped
                presetURL = preset.urlUnwrapped
                isEnabled = preset.isEnabled
                hasInitialized = true
            }
        }
    }

    private func saveAndDismiss() {
        if let preset = presetToEdit {
            preset.name = presetName
            if preset.urlUnwrapped.isEmpty {
                 preset.url = presetURL
            }
            preset.isEnabled = isEnabled
            PersistenceController.shared.saveViewContext()
            dismiss()
        } else {
            let newPreset = WebhookPreset.new(in: viewContext)
            newPreset.name = presetName
            newPreset.url = presetURL
            newPreset.isEnabled = isEnabled
            PersistenceController.shared.saveViewContext()
            onSaveNew?(newPreset)
        }
    }

    private func sendTestMessage() async {
        let data = WebhookManager.WebhookDataSnapshot(
            user: "Test User",
            substance: "Caffeine",
            substanceDisplayName: "Caffeine",
            dose: 100,
            units: "mg",
            isEstimate: false,
            route: "oral",
            site: "",
            simpleSite: "",
            note: "This is a test note."
        )
        let content = WebhookService.content(for: data, settings: .current)
        let result = await WebhookService.sendWebhookWithRetry(url: presetURL, content: content)
        if result.success {
            toastViewModel.showSuccessToast(message: "Test message sent.")
        } else if result.error as? WebhookService.DeliveryError == .unknownDelivery {
            toastViewModel.showErrorToast(message: "Couldn't confirm delivery. Check the webhook destination.")
        } else {
            toastViewModel.showErrorToast(message: "Couldn't send the test message.")
        }
    }
}
