import CoreData
import Foundation
import UniformTypeIdentifiers

extension SettingsScreen {
    struct ImportReview: Identifiable {
        enum Contents {
            case backup(JournalBackup)
            case journal(JournalFile)
        }

        let id = UUID()
        let filename: String
        let contents: Contents

        var isBackup: Bool {
            if case .backup = contents { return true }
            return false
        }

        var counts: JournalCounts {
            switch contents {
            case .backup(let backup): JournalCounts(backup)
            case .journal(let journal): JournalCounts(journal)
            }
        }
    }

    struct JournalCounts: Sendable {
        let experiences: Int
        let ingestions: Int
        let timedNotes: Int

        init(_ backup: JournalBackup) {
            experiences = backup.entities["Experience", default: []].count
            ingestions = backup.entities["Ingestion", default: []].count
            timedNotes = backup.entities["TimedNote", default: []].count
        }

        init(_ journal: JournalFile) {
            experiences = journal.experiences.count
            ingestions = journal.experiences.reduce(0) { $0 + $1.ingestions.count }
            timedNotes = journal.experiences.reduce(0) { $0 + $1.timedNotes.count }
        }
    }

    struct PreparedExport {
        let file: ExportedFile
        let counts: JournalCounts
    }

    @MainActor
    class ViewModel: ObservableObject {
        @Published var importReview: ImportReview?
        @Published var importError: String?
        @Published private(set) var isApplyingImport = false
        @Published private(set) var isPreparingImport = false
        weak var toastViewModel: ToastViewModel?

        // The journal in the format the Android app reads
        func exportData() async throws -> PreparedExport {
            try await export(contentType: .json, suffix: "") { context in
                let journal = try JournalFile(
                    experiences: context.fetch(PersistenceController.experiencesRequest(prefetchingIngestions: true)),
                    customSubstances: context.fetch(PersistenceController.customSubstancesRequest()),
                    customUnits: context.fetch(CustomUnit.fetchRequest()),
                    substanceOverrideRoas: context.fetch(PersistenceController.standaloneCustomRoasRequest()),
                    substanceOverrides: context.fetch(PersistenceController.substanceOverridesRequest()),
                    formulations: context.fetch(PersistenceController.formulationsRequest()))
                return (try JSONEncoder().encode(journal), JournalCounts(journal))
            }
        }

        func exportBackup() async throws -> PreparedExport {
            let appVersion = getCurrentAppVersion()
            return try await export(contentType: .freakLogBackup, suffix: " Backup") { context in
                let backup = try JournalBackup(context: context, appVersion: appVersion)
                return (try backup.fileData(), JournalCounts(backup))
            }
        }

        private func export(
            contentType: UTType,
            suffix: String,
            makeData: @escaping @Sendable (NSManagedObjectContext) throws -> (Data, JournalCounts)
        ) async throws -> PreparedExport {
            try PersistenceController.beginJournalOperation()
            defer { PersistenceController.endJournalOperation() }
            let (data, counts) = try await PersistenceController.shared.container.performBackgroundTask { context in
                try context.setQueryGenerationFrom(.current)
                return try makeData(context)
            }
            let file = ExportedFile(data: data, filename: "\(appName)\(suffix) \(Self.fileDate)", contentType: contentType)
            return PreparedExport(file: file, counts: counts)
        }

        private static var fileDate: String {
            Date().ISO8601Format(.iso8601(
                timeZone: TimeZone.current,
                dateSeparator: .dash,
                dateTimeSeparator: .standard,
                timeSeparator: .omitted))
        }

        func prepareImport(_ url: URL) {
            guard !isPreparingImport, !isApplyingImport else { return }
            importError = nil
            isPreparingImport = true
            Task {
                defer { isPreparingImport = false }
                do {
                    importReview = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let contents: ImportReview.Contents
                        if let backup = try JournalBackup.read(data) {
                            contents = .backup(backup)
                        } else {
                            contents = .journal(try JournalFile.read(data))
                        }
                        return ImportReview(filename: url.lastPathComponent, contents: contents)
                    }.value
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "The journal couldn’t be imported."
                }
            }
        }

        func importFile(_ review: ImportReview, removePublishedCopies: Bool) {
            guard !isApplyingImport, importReview?.id == review.id else { return }
            isApplyingImport = true
            importError = nil
            Task {
                defer { isApplyingImport = false }
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let container = PersistenceController.shared.container
                    let retainInFlightMessages = removePublishedCopies ? nil : WebhookManager.shared.makeInFlightRetentionCommit()
                    let removed: [UUID]
                    switch review.contents {
                    case .backup(let backup):
                        removed = try await container.performBackgroundTask { context in
                            try Self.replaceJournal(
                                in: context,
                                removePublishedCopies: removePublishedCopies,
                                retainInFlightMessages: retainInFlightMessages
                            ) {
                                try backup.restore(into: context)
                            }
                        }
                    case .journal(let file):
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
                    if case .backup(let backup) = review.contents {
                        await AnodyneClient.shared.applyInstanceChange { backup.restoreSettings() }
                        TabManager.shared.reload()
                        LeaderboardServerStore.shared.reload()
                    }
                    importReview = nil
                    showSuccessToast(message: review.isBackup ? "Backup Restored" : "Import Successful")
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "The journal couldn’t be imported."
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
