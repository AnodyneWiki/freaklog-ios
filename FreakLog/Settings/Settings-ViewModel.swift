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
        let counts: JournalCounts
        let dateRange: ClosedRange<Date>?
        let isProtected: Bool

        init(filename: String, contents: Contents, isProtected: Bool = false) {
            self.filename = filename
            self.contents = contents
            self.isProtected = isProtected
            switch contents {
            case .backup(let backup): counts = JournalCounts(backup)
            case .journal(let journal): counts = JournalCounts(journal)
            }
            dateRange = Self.dateRange(in: contents)
        }

        var isBackup: Bool {
            if case .backup = contents { return true }
            return false
        }

        var isEmptyJournal: Bool {
            counts.experiences == 0 && counts.ingestions == 0 && counts.timedNotes == 0
        }

        private static func dateRange(in contents: Contents) -> ClosedRange<Date>? {
            var range: ClosedRange<Date>?

            func include(_ date: Date?) {
                guard let date else { return }
                if let previous = range {
                    range = min(previous.lowerBound, date)...max(previous.upperBound, date)
                } else {
                    range = date...date
                }
            }

            switch contents {
            case .backup(let backup):
                var datedIngestions: Set<String> = []
                var experiencesWithDatedIngestions: Set<String> = []
                for record in backup.entities["Ingestion", default: []] {
                    if let date = record.date(for: "time") {
                        include(date)
                        datedIngestions.insert(record.id)
                        if let experienceID = record.relationships["experience"]?.string {
                            experiencesWithDatedIngestions.insert(experienceID)
                        }
                    }
                    include(record.date(for: "endTime"))
                }
                for record in backup.entities["Experience", default: []] {
                    // Older backups may describe the relationship from just one side.
                    let hasDatedIngestion = record.relationships["ingestions"]?.array?.contains {
                        $0.string.map(datedIngestions.contains) ?? false
                    } ?? false
                    if !hasDatedIngestion && !experiencesWithDatedIngestions.contains(record.id) {
                        include(record.date(for: "sortDate") ?? record.date(for: "creationDate"))
                    }
                }
                for record in backup.entities["TimedNote", default: []] {
                    include(record.date(for: "time"))
                }
                for record in backup.entities["ShulginRating", default: []] {
                    include(record.date(for: "time"))
                }
            case .journal(let journal):
                for experience in journal.experiences {
                    if experience.ingestions.isEmpty {
                        include(experience.sortDate ?? experience.creationDate)
                    }
                    for ingestion in experience.ingestions {
                        include(ingestion.time)
                        include(ingestion.endTime)
                    }
                    for note in experience.timedNotes {
                        include(note.time)
                    }
                    for rating in experience.ratings {
                        include(rating.time)
                    }
                }
            }
            return range
        }
    }

    struct JournalCounts: Sendable {
        let experiences: Int
        let ingestions: Int
        let timedNotes: Int
        let routines: Int
        let stockContainers: Int

        init(_ backup: JournalBackup) {
            experiences = backup.entities["Experience", default: []].count
            ingestions = backup.entities["Ingestion", default: []].count
            timedNotes = backup.entities["TimedNote", default: []].count
            routines = backup.entities["RoutineRecord", default: []].count
            stockContainers = backup.entities["StockContainer", default: []].count
        }

        init(_ journal: JournalFile) {
            experiences = journal.experiences.count
            ingestions = journal.experiences.reduce(0) { $0 + $1.ingestions.count }
            timedNotes = journal.experiences.reduce(0) { $0 + $1.timedNotes.count }
            routines = 0
            stockContainers = 0
        }
    }

    struct PreparedExport {
        let file: ExportedFile
        let counts: JournalCounts
    }

    enum ImportPurpose: Sendable {
        case restore, verify
    }

    struct LockedImport: Sendable {
        let data: Data
        let filename: String
        let purpose: ImportPurpose
    }

    @MainActor
    class ViewModel: ObservableObject {
        static let lastBackupDateKey = "lastJournalBackupDate"

        @Published private(set) var importReview: ImportReview?
        @Published private(set) var verifiedBackup: ImportReview?
        @Published private(set) var lockedImport: LockedImport?
        @Published private(set) var recoveryCopies: [JournalRecoveryBackups.Entry] = []
        @Published var isShowingImportDetails = false
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

        func protectBackup(_ file: ExportedFile, passphrase: String) async throws -> ExportedFile {
            let data = try await Task.detached(priority: .userInitiated) {
                try JournalBackupProtection.protect(file.data, passphrase: passphrase)
            }.value
            return ExportedFile(data: data, filename: file.filename, contentType: file.contentType)
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

        func prepareImport(_ url: URL, purpose: ImportPurpose = .restore) {
            guard !isPreparingImport, !isApplyingImport else { return }
            importError = nil
            isPreparingImport = true
            let model = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectModel
            Task {
                defer { isPreparingImport = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url)
                    }.value
                    if JournalBackupProtection.isProtected(data) {
                        try JournalBackupProtection.validateEnvelope(data)
                        lockedImport = LockedImport(data: data, filename: url.lastPathComponent, purpose: purpose)
                        isShowingImportDetails = true
                    } else {
                        let review = try await Task.detached(priority: .userInitiated) {
                            try Self.readImport(data, filename: url.lastPathComponent, purpose: purpose, model: model)
                        }.value
                        present(review, for: purpose)
                    }
                } catch {
                    reportOpenError(error)
                }
            }
        }

        func unlockImport(passphrase: String) {
            guard let lockedImport, !isPreparingImport, !isApplyingImport else { return }
            importError = nil
            isPreparingImport = true
            let model = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectModel
            Task {
                defer { isPreparingImport = false }
                do {
                    let review = try await Task.detached(priority: .userInitiated) {
                        let data = try JournalBackupProtection.open(lockedImport.data, passphrase: passphrase)
                        return try Self.readImport(
                            data, filename: lockedImport.filename, purpose: lockedImport.purpose,
                            model: model, isProtected: true)
                    }.value
                    self.lockedImport = nil
                    present(review, for: lockedImport.purpose)
                } catch {
                    reportOpenError(error)
                }
            }
        }

        func prepareRecoveryBackup(_ entry: JournalRecoveryBackups.Entry) {
            guard !isPreparingImport, !isApplyingImport else { return }
            importError = nil
            isPreparingImport = true
            let model = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectModel
            let name = entry.created.formatted(date: .abbreviated, time: .shortened)
            Task {
                defer { isPreparingImport = false }
                do {
                    let review = try await Task.detached(priority: .userInitiated) {
                        let data = try JournalRecoveryBackups.open(entry.url)
                        return try Self.readImport(data, filename: name, purpose: .restore, model: model, isProtected: true)
                    }.value
                    present(review, for: .restore)
                } catch {
                    reportOpenError(error)
                }
            }
        }

        func clearImportDetails() {
            lockedImport = nil
            importReview = nil
            verifiedBackup = nil
            importError = nil
        }

        func refreshRecoveryCopies() {
            recoveryCopies = (try? JournalRecoveryBackups.entries()) ?? []
        }

        private func present(_ review: ImportReview, for purpose: ImportPurpose) {
            switch purpose {
            case .restore: importReview = review
            case .verify: verifiedBackup = review
            }
            isShowingImportDetails = true
        }

        private func reportOpenError(_ error: Error) {
            if error is DecodingError {
                importError = "This file couldn’t be read as a journal. It may be damaged or incomplete."
            } else {
                importError = (error as? LocalizedError)?.errorDescription ?? "This journal file couldn’t be opened or validated."
            }
        }

        private nonisolated static func readImport(
            _ data: Data, filename: String, purpose: ImportPurpose, model: NSManagedObjectModel, isProtected: Bool = false
        ) throws -> ImportReview {
            let contents: ImportReview.Contents
            if let backup = try JournalBackup.read(data) {
                try backup.validateContents(in: model)
                contents = .backup(backup)
            } else {
                guard purpose == .restore, !isProtected else { throw JournalBackupError.unrecognizedFormat }
                contents = .journal(try JournalFile.read(data))
            }
            return ImportReview(filename: filename, contents: contents, isProtected: isProtected)
        }

        func importFile(_ review: ImportReview, removePublishedCopies: Bool, saveRecoveryCopy: Bool) {
            guard !isApplyingImport, importReview?.id == review.id else { return }
            isApplyingImport = true
            importError = nil
            Task {
                defer { isApplyingImport = false }
                do {
                    try PersistenceController.beginJournalOperation()
                    defer { PersistenceController.endJournalOperation() }
                    let container = PersistenceController.shared.container
                    let recoveryAppVersion = saveRecoveryCopy ? getCurrentAppVersion() : nil
                    let retainInFlightMessages = removePublishedCopies ? nil : WebhookManager.shared.makeInFlightRetentionCommit()
                    let removed: [UUID]
                    switch review.contents {
                    case .backup(let backup):
                        removed = try await container.performBackgroundTask { context in
                            try Self.replaceJournal(
                                in: context,
                                removePublishedCopies: removePublishedCopies,
                                retainInFlightMessages: retainInFlightMessages,
                                recoveryAppVersion: recoveryAppVersion
                            ) {
                                try backup.restore(into: context)
                            }
                        }
                    case .journal(let file):
                        removed = try await container.performBackgroundTask { context in
                            let removed = try Self.replaceJournal(
                                in: context,
                                removePublishedCopies: removePublishedCopies,
                                retainInFlightMessages: retainInFlightMessages,
                                recoveryAppVersion: recoveryAppVersion
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
                    isShowingImportDetails = false
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
            recoveryAppVersion: String? = nil,
            replace: () throws -> Void
        ) throws -> [UUID] {
            try PersistenceController.withJournalStoreWrite {
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                var didSave = false
                defer { if !didSave { context.rollback() } }
                let outgoingIDs = removePublishedCopies ? try ingestionIDs(in: context) : []
                let outgoingMessages = removePublishedCopies ? try messageDestinations(in: context) : []
                if let recoveryAppVersion {
                    try saveRecoveryCopy(in: context, appVersion: recoveryAppVersion)
                }
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

        private nonisolated static func saveRecoveryCopy(in context: NSManagedObjectContext, appVersion: String) throws {
            do {
                guard let model = context.persistentStoreCoordinator?.managedObjectModel else {
                    throw JournalRecoveryBackups.Failure.cannotSave
                }
                let backup = try JournalBackup(context: context, appVersion: appVersion)
                try backup.validateContents(in: model)
                try JournalRecoveryBackups.saveVerified(backup.fileData())
            } catch {
                throw JournalRecoveryBackups.Failure.cannotSave
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
                    do {
                        try JournalRecoveryBackups.removeAll()
                        refreshRecoveryCopies()
                        showSuccessToast(message: "Delete Successful")
                    } catch {
                        refreshRecoveryCopies()
                        showErrorToast(message: "The journal was deleted, but the recovery copies couldn’t be removed.")
                    }
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
