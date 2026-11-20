import CoreData
import SwiftUI

struct WebhooksScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.activeWebhookPresetsRequest(), animation: .default)
    private var presets: FetchedResults<WebhookPreset>

    @AppStorage(PersistenceController.webhookUsernameKey) private var webhookUsername: String = ""
    @AppStorage(PersistenceController.webhookTemplateKey) private var webhookTemplate: String = WebhookService.defaultTemplate
    @AppStorage(PersistenceController.webhookIsHyperlinkedKey) private var isHyperlinked: Bool = false
    @AppStorage(PersistenceController.webhookSubstanceInfoUrlKey) private var substanceInfoUrl: String = ""

    @State private var presetToEdit: WebhookPreset?
    @State private var isCreatingNewPreset = false

    var body: some View {
        Form {
            Section {
                if presets.isEmpty {
                    Text("No webhooks configured.")
                        .foregroundColor(.secondary)
                }
                ForEach(presets) { preset in
                    NavigationLink {
                        EditWebhookPresetScreen(preset: preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.nameUnwrapped.isEmpty ? "Unnamed" : preset.nameUnwrapped)
                                    .font(.headline)
                            }
                            Spacer()
                            if preset.isEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button {
                            archivePreset(preset)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.indigo)
                    }
                }
            } header: {
                Text("Webhooks")
            } footer: {
                Text("Configure multiple Discord webhooks. You can select which ones to use when finishing an ingestion.")
            }

            Section(
                header: Text("Username"),
                footer: Text("The name used for webhook messages. Gets overridden if a name is entered during ingestion.")
            ) {
                TextField("Benjamin Engel", text: $webhookUsername)
                    .textInputAutocapitalization(.words)
            }

            Section(
                header: Text("Links"),
                footer: Text("If enabled, the substance name becomes clickable.")
            ) {
                Toggle("Hyperlink Substance Name", isOn: $isHyperlinked)
                    .tint(.accentColor)

                if isHyperlinked {
                    TextField("Base URL", text: $substanceInfoUrl)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section(
                header: Text("Message Layout"),
                footer: Text("Variables: {user}, {dose}, {unit}, {substance}, {route}, {site}, {note}")
            ) {
                TextEditor(text: $webhookTemplate)
                    .frame(minHeight: 100)
                    .font(.system(.body, design: .monospaced))

                Button("Reset to Default") {
                    webhookTemplate = WebhookService.defaultTemplate
                }
                .font(.caption)
            }
        }
        .navigationTitle("Webhooks")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: GlobalNavigationDestination.webhookArchive) {
                    Label("Archive", systemImage: "archivebox")
                }

                Button {
                    isCreatingNewPreset = true
                } label: {
                    Label("Add Webhook", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreatingNewPreset) {
            NavigationStack {
                EditWebhookPresetScreen(isNewPreset: true, onSave: { preset in
                    isCreatingNewPreset = false
                }, onCancel: {
                    isCreatingNewPreset = false
                })
            }
        }
        .sheet(item: $presetToEdit) { preset in
            NavigationStack {
                EditWebhookPresetScreen(preset: preset)
            }
        }
    }

    private func archivePreset(_ preset: WebhookPreset) {
        preset.isArchived = true
        PersistenceController.shared.saveViewContext()
    }
}

