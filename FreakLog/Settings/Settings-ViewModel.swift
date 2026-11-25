import CoreData
import Foundation

extension SettingsScreen {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var isExporting = false
        @Published var exportedFile = ExportedFile()
        weak var toastViewModel: ToastViewModel?

        // The journal in the format the Android app reads
        func exportData() {
            let pc = PersistenceController.shared
            let journalFile = JournalFile(
                experiences: pc.getAllExperiences(),
                customSubstances: pc.getAllCustomSubstances(),
                customUnits: pc.getAllCustomUnits(),
                substanceOverrideRoas: pc.getAllStandaloneCustomRoas(),
                substanceOverrides: (try? pc.viewContext.fetch(PersistenceController.substanceOverridesRequest())) ?? [],
                formulations: pc.getAllFormulations())
            do {
                exportedFile = try ExportedFile(data: JSONEncoder().encode(journalFile), filename: "\(appName) \(Self.fileDate)")
                isExporting = true
            } catch {
                showErrorToast(message: "Export Failed")
            }
        }

        // Everything, to restore exactly
        func exportBackup() {
            let appVersion = getCurrentAppVersion()
            Task {
                do {
                    let data = try await PersistenceController.shared.container.performBackgroundTask { context in
                        try JournalBackup(context: context, appVersion: appVersion).fileData()
                    }
                    exportedFile = ExportedFile(data: data, filename: "\(appName) Backup \(Self.fileDate)", contentType: .freakLogBackup)
                    isExporting = true
                } catch {
                    print("Backup failed: \(error)")
                    showErrorToast(message: "Backup Failed")
                }
            }
        }

        private static var fileDate: String {
            Date().ISO8601Format(.iso8601(
                timeZone: TimeZone.current,
                dateSeparator: .dash,
                dateTimeSeparator: .standard,
                timeSeparator: .omitted))
        }

        // Restores a backup exactly, settings included: everything is replaced in one save, so a backup that can't be
        // restored leaves the journal as it was
        private func importBackup(_ backup: JournalBackup) async {
            let container = PersistenceController.shared.container
            let result: Result<Void, Error> = await container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    try backup.restore(into: context)
                    try context.save()
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            switch result {
            case .success:
                await AnodyneClient.shared.applyInstanceChange {
                    backup.restoreSettings()
                }
                TabManager.shared.reload()
                LeaderboardServerStore.shared.reload()
                showSuccessToast(message: "Backup Restored")
            case .failure(let error):
                print("Restoring the backup failed: \(error)")
                showErrorToast(message: (error as? JournalBackupError)?.errorDescription ?? "Import Failed")
            }
        }

        func importFile(_ url: URL) {
            Task {
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let data = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url)
                    }.value
                    let container = PersistenceController.shared.container

                    // A backup restores everything; other files are journal files
                    if let backup = try await Task.detached(priority: .userInitiated, operation: {
                        try JournalBackup.read(data)
                    }).value {
                        await importBackup(backup)
                        return
                    }

                    // Decode off the main thread first; the view model, and so this task, is main-actor isolated
                    let file = try await Task.detached(priority: .userInitiated) {
                        try JournalFile.read(data)
                    }.value
                    
                    try await container.performBackgroundTask { context in
                        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                        try file.replaceJournal(in: context)
                    }
                    showSuccessToast(message: "Import Successful")
                } catch {
                    print("Import failed: \(error)")
                    showErrorToast(message: (error as? LocalizedError)?.errorDescription ?? "Import Failed")
                }
            }
        }

        func deleteEverything() {
            Task {
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let persistence = PersistenceController.shared
                    let container = persistence.container
                    let ingestions = try persistence.viewContext.fetch(Ingestion.fetchRequest())
                    let notes = try persistence.viewContext.fetch(TimedNote.fetchRequest())
                    let cleanUp = await IngestionDeletion.remoteCleanUp(for: ingestions, timedNotes: notes)
                    try await container.performBackgroundTask { context in
                        try PersistenceController.stageJournalDeletion(in: context)
                        try context.save()
                        PersistenceController.purgeLocalHistory(in: context)
                    }
                    cleanUp()
                    await WebhookManager.shared.deleteAllPresetsAndMessages()
                    showSuccessToast(message: "Delete Successful")
                } catch {
                    showErrorToast(message: (error as? LocalizedError)?.errorDescription ?? "Delete Failed")
                }
            }
        }

        private func showSuccessToast(message: String) {
            toastViewModel?.showSuccessToast(message: message)
        }

        private func showErrorToast(message: String) {
            toastViewModel?.showErrorToast(message: message)
        }
    }
}
