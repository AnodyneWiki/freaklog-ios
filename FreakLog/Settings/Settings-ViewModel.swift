import CoreData
import Foundation
import UniformTypeIdentifiers

extension SettingsScreen {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var isExporting = false
        @Published var exportedFile = ExportedFile()
        weak var toastViewModel: ToastViewModel?

        // The journal in the format the Android app reads
        func exportData() {
            export(contentType: .json, suffix: "") { context in
                let journal = try JournalFile(
                    experiences: context.fetch(PersistenceController.experiencesRequest(prefetchingIngestions: true)),
                    customSubstances: context.fetch(PersistenceController.customSubstancesRequest()),
                    customUnits: context.fetch(CustomUnit.fetchRequest()),
                    substanceOverrideRoas: context.fetch(PersistenceController.standaloneCustomRoasRequest()),
                    substanceOverrides: context.fetch(PersistenceController.substanceOverridesRequest()),
                    formulations: context.fetch(PersistenceController.formulationsRequest()))
                return try JSONEncoder().encode(journal)
            }
        }

        func exportBackup() {
            let appVersion = getCurrentAppVersion()
            export(contentType: .freakLogBackup, suffix: " Backup") { context in
                try JournalBackup(context: context, appVersion: appVersion).fileData()
            }
        }

        private func export(
            contentType: UTType,
            suffix: String,
            makeData: @escaping @Sendable (NSManagedObjectContext) throws -> Data
        ) {
            Task {
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let data = try await PersistenceController.shared.container.performBackgroundTask { context in
                        try context.setQueryGenerationFrom(.current)
                        return try makeData(context)
                    }
                    exportedFile = ExportedFile(data: data, filename: "\(appName)\(suffix) \(Self.fileDate)", contentType: contentType)
                    isExporting = true
                } catch {
                    showErrorToast(message: (error as? LocalizedError)?.errorDescription ?? "Export Failed")
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

        func importFile(_ url: URL, removePublishedCopies: Bool) {
            Task {
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let data = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url)
                    }.value
                    let backup = try await Task.detached(priority: .userInitiated) { try JournalBackup.read(data) }.value
                    let container = PersistenceController.shared.container
                    let retainInFlightMessages = removePublishedCopies ? nil : WebhookManager.shared.makeInFlightRetentionCommit()
                    let removed: [UUID]
                    if let backup {
                        removed = try await container.performBackgroundTask { context in
                            try Self.replaceJournal(
                                in: context,
                                removePublishedCopies: removePublishedCopies,
                                retainInFlightMessages: retainInFlightMessages
                            ) {
                                try backup.restore(into: context)
                            }
                        }
                    } else {
                        let file = try await Task.detached(priority: .userInitiated) { try JournalFile.read(data) }.value
                        removed = try await container.performBackgroundTask { context in
                            let removed = try Self.replaceJournal(
                                in: context,
                                removePublishedCopies: removePublishedCopies,
                                retainInFlightMessages: retainInFlightMessages
                            ) {
                                try PersistenceController.stageJournalDeletion(in: context)
                                file.insert(into: context)
                            }
                            PersistenceController.purgeLocalHistory(in: context)
                            return removed
                        }
                    }
                    LeaderboardSyncManager.shared.journalWasReplaced()
                    if removePublishedCopies { IngestionDeletion.didDelete(identifiers: removed) }
                    if let backup {
                        backup.restoreSettings()
                        TabManager.shared.reload()
                        LeaderboardServerStore.shared.reload()
                    }
                    showSuccessToast(message: backup == nil ? "Import Successful" : "Backup Restored")
                } catch {
                    showErrorToast(message: (error as? LocalizedError)?.errorDescription ?? "Import Failed")
                }
            }
        }

        nonisolated static func replaceJournal(
            in context: NSManagedObjectContext,
            removePublishedCopies: Bool,
            retainInFlightMessages: (@Sendable () -> Void)? = nil,
            replace: () throws -> Void
        ) throws -> [UUID] {
            try PersistenceController.withJournalStoreWrite {
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                var didSave = false
                defer { if !didSave { context.rollback() } }
                let outgoingIDs = removePublishedCopies ? try ingestionIDs(in: context) : []
                let outgoingMessages = removePublishedCopies ? try messageDestinations(in: context) : []
                try replace()
                context.processPendingChanges()
                let removedIDs = removePublishedCopies ? outgoingIDs.subtracting(try ingestionIDs(in: context)) : []
                if removePublishedCopies {
                    for destination in outgoingMessages.subtracting(try messageDestinations(in: context)) {
                        destination.stage(in: context)
                    }
                }
                try context.save()
                didSave = true
                retainInFlightMessages?()
                return Array(removedIDs)
            }
        }

        private nonisolated static func ingestionIDs(in context: NSManagedObjectContext) throws -> Set<UUID> {
            try Set(context.fetch(Ingestion.fetchRequest()).compactMap(\.identifier))
        }

        private nonisolated static func messageDestinations(in context: NSManagedObjectContext) throws -> Set<WebhookManager.Destination> {
            try Set(context.fetch(WebhookMessage.fetchRequest()).compactMap(WebhookManager.Destination.init))
        }

        func deleteEverything() {
            Task {
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let container = PersistenceController.shared.container
                    let identifiers = try await container.performBackgroundTask { context in
                        try PersistenceController.withJournalStoreWrite {
                            let ingestions = try context.fetch(Ingestion.fetchRequest())
                            let notes = try context.fetch(TimedNote.fetchRequest())
                            let identifiers = ingestions.compactMap(\.identifier)
                            WebhookManager.stageMessageDeletion(for: ingestions, timedNotes: notes, in: context)
                            try WebhookManager.stageAllPresetDeletion(in: context)
                            try PersistenceController.stageJournalDeletion(in: context)
                            try context.save()
                            PersistenceController.purgeLocalHistory(in: context)
                            return identifiers
                        }
                    }
                    IngestionDeletion.didDelete(identifiers: identifiers)
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
