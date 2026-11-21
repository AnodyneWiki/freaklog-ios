import SwiftUI

struct WebhookArchiveScreen: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(fetchRequest: PersistenceController.archivedWebhookPresetsRequest(), animation: .default)
    private var archivedPresets: FetchedResults<WebhookPreset>
    
    @State private var presetToDelete: WebhookPreset?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Group {
            if archivedPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No archived webhooks")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(archivedPresets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text(preset.urlUnwrapped)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                restorePreset(preset)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                presetToDelete = preset
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Archive")
        .confirmationDialog(
            "Delete Webhook?",
            isPresented: $showingDeleteConfirmation,
            presenting: presetToDelete
        ) { preset in
            Button("Delete Preset Only", role: .destructive) {
                deletePreset(preset, deleteMessages: false)
            }
            
            Button("Delete & Cleanup Messages", role: .destructive) {
                deletePreset(preset, deleteMessages: true)
            }
            
            Button("Cancel", role: .cancel) {
                presetToDelete = nil
            }
        } message: { preset in
            Text("Do you want to permanently delete \"\(preset.nameUnwrapped)\"? You can also choose to delete all messages sent by this webhook.")
        }
    }
    
    private func restorePreset(_ preset: WebhookPreset) {
        preset.isArchived = false
        PersistenceController.shared.saveViewContext()
    }
    
    private func deletePreset(_ preset: WebhookPreset, deleteMessages: Bool) {
        Task {
            await WebhookManager.shared.deletePreset(preset, deletingMessages: deleteMessages)
        }
    }
}
