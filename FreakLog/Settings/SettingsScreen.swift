import AlertToast
import SwiftUI
import AppIntents
import UIKit

struct SettingsScreen: View {
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject var authenticator: Authenticator
    @EnvironmentObject private var toastViewModel: ToastViewModel

    var body: some View {
        SettingsContent(isFaceIDAvailable: authenticator.isFaceIDEnabled, viewModel: viewModel)
            .onAppear {
                viewModel.toastViewModel = toastViewModel
            }
    }
}

struct SettingsContent: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    let isFaceIDAvailable: Bool
    @ObservedObject var viewModel: SettingsScreen.ViewModel

    var body: some View {
        List {
            Section {
                NavigationLink {
                    JournalDataSettings(viewModel: viewModel)
                } label: {
                    Label("Journal Data", systemImage: "externaldrive")
                }
                NavigationLink {
                    PrivacyLockSettings(isFaceIDAvailable: isFaceIDAvailable)
                } label: {
                    Label("Privacy & Lock", systemImage: "lock.shield")
                }
            }
            if UIApplication.shared.supportsAlternateIcons || isEyeOpen {
                Section("Appearance") {
                    if UIApplication.shared.supportsAlternateIcons {
                        NavigationLink(value: GlobalNavigationDestination.appIconSettings) {
                            Label("App Icon", systemImage: "app")
                        }
                    }
                    if isEyeOpen {
                        NavigationLink(value: GlobalNavigationDestination.tabSettings) {
                            Label("Customize Tabs", systemImage: "rectangle.stack")
                        }
                    }
                }
            }
            if isEyeOpen {
                Section("Journal") {
                    NavigationLink(value: GlobalNavigationDestination.journalSettings) {
                        Label("Journal & Timeline", systemImage: "list.dash.header.rectangle")
                    }
                    NavigationLink(value: GlobalNavigationDestination.customUnits) {
                        Label("Custom Units", systemImage: "pills")
                    }
                    NavigationLink(value: GlobalNavigationDestination.formulations) {
                        Label("Formulations", systemImage: "testtube.2")
                    }
                }
                Section("Integrations") {
                    NavigationLink(value: GlobalNavigationDestination.webhookSettings) {
                        Label("Webhooks", systemImage: "network")
                    }
                    NavigationLink(value: GlobalNavigationDestination.anodyneSettings) {
                        Label("AnodyneWiki", systemImage: "books.vertical")
                    }
                    NavigationLink(value: GlobalNavigationDestination.assistantSettings) {
                        Label("Assistant", systemImage: "text.bubble")
                    }
                    NavigationLink(value: GlobalNavigationDestination.leaderboardServers) {
                        Label("Leaderboard", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            Section {
                NavigationLink {
                    JournalHelpScreen(isEyeOpen: isEyeOpen)
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    WhatsNewScreen(isEyeOpen: isEyeOpen)
                } label: {
                    LabeledContent {
                        Text(getCurrentAppVersion())
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("What’s New", systemImage: "sparkles")
                    }
                }
            }
            if isEyeOpen {
                Section("Communication") {
                    Link(destination: URL(string: repoUrl)!) {
                        Label("Source Code", systemImage: "doc.text.magnifyingglass")
                    }
                    Link(destination: URL(string: communityUrl)!) {
                        Label("Join Community", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Link(destination: URL(string: issuesUrl)!) {
                        Label("Report an issue", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    }
                }
            }
            eye
        }
        .navigationTitle("Settings")
    }

    private var eye: some View {
        HStack {
            Spacer()
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80, alignment: .center)
                .onTapGesture(count: 3, perform: toggleEye)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    private var imageName: String {
        isEyeOpen ? "Eye Open" : "Eye Closed"
    }

    private func toggleEye() {
        isEyeOpen.toggle()
        NotificationCenter.default.post(name: Notification.eyeName, object: nil)
        playHapticFeedback()
    }
}

private struct PrivacyLockSettings: View {
    let isFaceIDAvailable: Bool
    @AppStorage(PersistenceController.hasToUnlockAppKey) private var requiresUnlock = false
    @AppStorage(PersistenceController.lockTimeOptionKey) private var lockTimeOption: LockTimeOption = .after5Minutes

    var body: some View {
        List {
            Section {
                if isFaceIDAvailable {
                    Toggle("Require App Unlock", isOn: $requiresUnlock.animation())
                        .tint(.accentColor)
                    if requiresUnlock {
                        Picker("Lock After", selection: $lockTimeOption) {
                            ForEach(LockTimeOption.allCases) { option in
                                Text(option.text).tag(option)
                            }
                        }
                    }
                } else {
                    Text("Set up device authentication in Settings to lock FreakLog.")
                }
            }
        }
        .navigationTitle("Privacy & Lock")
    }
}

private struct JournalHelpScreen: View {
    let isEyeOpen: Bool

    var body: some View {
        List {
            Section("Privacy") {
                Text("Your journal is stored on this device by default. You can turn on iCloud Sync in Journal Data.")
            }
            Section("Backups") {
                Text("Use Journal Data to export a backup or restore from a file.")
            }
            if isEyeOpen {
                Section {
                    NavigationLink(value: GlobalNavigationDestination.saferUse) {
                        Label("Safer Use", systemImage: "heart.text.clipboard")
                    }
                    NavigationLink(value: GlobalNavigationDestination.faq) {
                        Label("Frequently Asked Questions", systemImage: "questionmark.circle")
                    }
                }
            }
        }
        .navigationTitle("Help")
    }
}

private struct WhatsNewScreen: View {
    let isEyeOpen: Bool

    var body: some View {
        List {
            Section("Version \(getCurrentAppVersion())") {
                releaseNote("Backup Review", description: "Review a backup’s contents before restoring it.")
                if UIApplication.shared.supportsAlternateIcons {
                    releaseNote("App Icon", description: "Choose an alternate icon in Appearance.")
                }
                if isEyeOpen {
                    releaseNote("Markdown Reports", description: "Edit your experience report before sharing it.")
                }
            }
        }
        .navigationTitle("What’s New")
    }

    private func releaseNote(_ title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct JournalDataSettings: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @State private var isChoosingFile = false
    @State private var isConfirmingDeletion = false
    @State private var filePurpose: SettingsScreen.ImportPurpose = .restore
    @AppStorage(SettingsScreen.ViewModel.lastBackupDateKey) private var lastBackupTime = 0.0
    // PersistenceController reads this with bool(forKey:), so unset means off.
    @AppStorage(PersistenceController.isICloudSyncEnabledKey) private var isICloudSyncEnabled = false
    @EnvironmentObject private var toastViewModel: ToastViewModel

    var body: some View {
        List {
            Section {
                Toggle("iCloud Sync", isOn: Binding(get: { isICloudSyncEnabled }, set: { enabled in
                    do {
                        try PersistenceController.shared.updateCloudKitSyncStatus(enabled)
                    } catch {
                        toastViewModel.showErrorToast(message: "Couldn't Change iCloud Sync")
                    }
                }))
                .tint(.accentColor)
            } header: {
                Text("Sync")
            } footer: {
                Text("Sync your journal across devices using iCloud.")
            }
            Section {
                Button {
                    chooseFile(for: .restore)
                } label: {
                    if viewModel.preparingImportFor == .restore {
                        ProgressView("Reading File…")
                    } else {
                        Label("Restore from File…", systemImage: "arrow.down.doc")
                    }
                }
                .disabled(viewModel.isPreparingImport || viewModel.isApplyingImport)
                if let error = viewModel.fileErrors[.restore] {
                    Label(error, systemImage: "exclamationmark.circle")
                }
                if !viewModel.recoveryCopies.isEmpty {
                    Menu {
                        ForEach(viewModel.recoveryCopies) { entry in
                            Button(entry.created.formatted(date: .abbreviated, time: .shortened)) {
                                viewModel.prepareRecoveryBackup(entry)
                            }
                        }
                    } label: {
                        Label("Recovery Copies", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(viewModel.isPreparingImport || viewModel.isApplyingImport)
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Preview a backup or journal file before replacing your current journal.")
            }
            Section("Export") {
                NavigationLink {
                    JournalExportReview(viewModel: viewModel, isBackup: true)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("FreakLog Backup")
                            Text("Journal and settings").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                }
                NavigationLink {
                    JournalExportReview(viewModel: viewModel, isBackup: false)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Journal JSON")
                            Text("Entries and substance definitions").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            Section("Reports") {
                NavigationLink {
                    SelectiveExportScreen()
                } label: {
                    Label("Journal Summary", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    SelectiveExportScreen(kind: .clinician)
                } label: {
                    Label("Clinician Summary", systemImage: "stethoscope")
                }
            }
            Section("Compatibility") {
                NavigationLink {
                    JournalTransferCompatibilityScreen(viewModel: viewModel)
                } label: {
                    Label("Transfer Compatibility", systemImage: "arrow.left.arrow.right")
                }
            }
            Section("Presets") {
                NavigationLink {
                    JournalPresetTransferScreen()
                } label: {
                    Label("Share Presets", systemImage: "square.and.arrow.up.on.square")
                }
            }
            Section {
                NavigationLink {
                    JournalAutomaticBackupScreen()
                } label: {
                    Label("Automatic Backups", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    chooseFile(for: .verify)
                } label: {
                    if viewModel.preparingImportFor == .verify {
                        ProgressView("Verifying Backup…")
                    } else {
                        Label("Verify Backup…", systemImage: "checkmark.shield")
                    }
                }
                .disabled(viewModel.isPreparingImport || viewModel.isApplyingImport)
                if let error = viewModel.fileErrors[.verify] {
                    Label(error, systemImage: "exclamationmark.circle")
                }
                if lastBackupTime > 0 {
                    LabeledContent(
                        "Last Saved Backup",
                        value: Date(timeIntervalSince1970: lastBackupTime).formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Manage Backups")
            }
            Section {
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete Journal Data…", systemImage: "trash")
                }
                .disabled(viewModel.isPreparingImport || viewModel.isApplyingImport)
            }
        }
        .navigationTitle("Journal Data")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ExportedFile.readableContentTypes) { result in
            switch result {
            case .success(let url): viewModel.prepareImport(url, purpose: filePurpose)
            case .failure: viewModel.reportFileSelectionFailure(for: filePurpose)
            }
        }
        .sheet(isPresented: $viewModel.isShowingImportDetails, onDismiss: {
            viewModel.clearImportDetails()
            viewModel.refreshRecoveryCopies()
        }) {
            JournalImportDetails(viewModel: viewModel)
        }
        .onAppear(perform: viewModel.refreshRecoveryCopies)
        .confirmationDialog("Delete Journal Data?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: viewModel.deleteEverything)
        } message: {
            if isEyeOpen {
                Text("This will delete your journal, attached lab reports, and on-device recovery copies.")
            } else {
                Text("This will delete your journal and its on-device recovery copies.")
            }
        }
    }

    private func chooseFile(for purpose: SettingsScreen.ImportPurpose) {
        filePurpose = purpose
        isChoosingFile = true
    }
}

private struct JournalImportDetails: View {
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""

    var body: some View {
        Group {
            if let review = viewModel.importReview {
                JournalImportReview(review: review, viewModel: viewModel)
            } else if let backup = viewModel.verifiedBackup {
                NavigationStack {
                    Form {
                        Section {
                            Label("This backup can be restored.", systemImage: "checkmark.shield")
                            LabeledContent("Name", value: backup.filename)
                            JournalCountsRows(counts: backup.counts)
                        }
                    }
                    .navigationTitle("Backup Verified")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            } else if let lockedImport = viewModel.lockedImport {
                NavigationStack {
                    Form {
                        Section {
                            LabeledContent("Name", value: lockedImport.filename)
                            SecureField("Passphrase", text: $passphrase)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(viewModel.isPreparingImport)
                                .onSubmit(unlock)
                        }
                        if viewModel.isPreparingImport {
                            ProgressView("Opening File…")
                        } else if let error = viewModel.importError {
                            Label(error, systemImage: "exclamationmark.circle")
                        }
                    }
                    .navigationTitle("Protected File")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.disabled(viewModel.isPreparingImport)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Open", action: unlock)
                                .disabled(!canUnlock)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isPreparingImport || viewModel.isApplyingImport)
    }

    private var canUnlock: Bool {
        !passphrase.isEmpty && !viewModel.isPreparingImport
    }

    private func unlock() {
        guard canUnlock else { return }
        viewModel.unlockImport(passphrase: passphrase)
        passphrase = ""
    }
}

private struct JournalImportReview: View {
    let review: SettingsScreen.ImportReview
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var removePublishedCopies = false
    @State private var saveRecoveryCopy = true
    @State private var isConfirmingReplacement = false

    private var replacementImpact: LocalizedStringKey {
        if review.isEmptyJournal {
            return review.isBackup
                ? "This backup will clear your journal and replace your backed-up settings."
                : "This file will clear your journal."
        }
        return review.isBackup
            ? "Restoring this backup replaces your current journal and backed-up settings."
            : "Restoring this file replaces your current journal."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    LabeledContent("Format", value: review.isBackup ? "FreakLog Backup" : "Journal JSON")
                    LabeledContent("Name", value: review.filename)
                    if review.isProtected {
                        Label("Encrypted", systemImage: "lock")
                    }
                }
                Section("Incoming Journal") {
                    JournalCountsRows(counts: review.counts)
                    LabeledContent("Date Range") {
                        if let range = review.dateRange {
                            Text((range.lowerBound..<range.upperBound).formatted(.interval.year().month(.abbreviated).day()))
                        } else {
                            Text("No dated entries")
                        }
                    }
                    if review.isEmptyJournal {
                        Label("This file contains no experiences, ingestions, or timed notes.", systemImage: "exclamationmark.triangle")
                    }
                    Text(replacementImpact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !review.transferOmissions.isEmpty {
                    Section("Transfer Notes") {
                        ForEach(review.transferOmissions, id: \.self) { omission in
                            Text(omission)
                        }
                    }
                }
                Section {
                    Toggle("Remove Published Copies", isOn: $removePublishedCopies)
                } header: {
                    Text("Publishing")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This removes published copies of discarded entries from supported integrations.")
                        if !review.isBackup {
                            Text("Keeping old copies can result in duplicates on the next leaderboard sync.")
                        }
                    }
                }
                Section {
                    Toggle("Save a Recovery Copy", isOn: $saveRecoveryCopy)
                } footer: {
                    Text("Keep an encrypted copy of your current journal on this device before replacing it.")
                }
                Section {
                    if let error = viewModel.importError {
                        Label(error, systemImage: "exclamationmark.circle")
                    }
                    if viewModel.isApplyingImport {
                        ProgressView("Replacing Journal…")
                    } else {
                        Button(viewModel.importError == nil ? "Replace Journal" : "Try Again", role: .destructive) {
                            isConfirmingReplacement = true
                        }
                    }
                }
            }
            .disabled(viewModel.isApplyingImport)
            .navigationTitle("Review Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isApplyingImport)
                }
            }
            .confirmationDialog("Replace Journal?", isPresented: $isConfirmingReplacement, titleVisibility: .visible) {
                Button("Replace Journal", role: .destructive) {
                    viewModel.importFile(
                        review, removePublishedCopies: removePublishedCopies, saveRecoveryCopy: saveRecoveryCopy)
                }
            } message: {
                Text(replacementImpact)
            }
        }
        .interactiveDismissDisabled(viewModel.isApplyingImport)
    }
}

private struct JournalCountsRows: View {
    let counts: SettingsScreen.JournalCounts

    var body: some View {
        LabeledContent("Experiences", value: counts.experiences.formatted())
        LabeledContent("Ingestions", value: counts.ingestions.formatted())
        LabeledContent("Timed Notes", value: counts.timedNotes.formatted())
        if counts.routines > 0 {
            LabeledContent("Routines", value: counts.routines.formatted())
        }
        if counts.stockContainers > 0 {
            LabeledContent("Stock Containers", value: counts.stockContainers.formatted())
        }
    }
}

struct JournalExportReview: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    let viewModel: SettingsScreen.ViewModel
    @EnvironmentObject private var toastViewModel: ToastViewModel
    let isBackup: Bool
    var isAndroidTransfer = false
    var pwJournalVersion: PWJournalTransferVersion? = nil
    @State private var preparation = UUID()
    @State private var prepared: SettingsScreen.PreparedExport?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var exportDocument: ExportedFile?
    @State private var protectsBackup = true
    @State private var passphrase = ""
    @State private var confirmedPassphrase = ""
    @State private var isProtecting = false
    @AppStorage(SettingsScreen.ViewModel.lastBackupDateKey) private var lastBackupTime = 0.0

    private var formatName: String {
        if let pwJournalVersion { return pwJournalVersion.name }
        if isAndroidTransfer { return "Android Transfer" }
        return isBackup ? "FreakLog Backup" : "Journal JSON"
    }
    private var requiresPassphrase: Bool { (isBackup || isAndroidTransfer) && protectsBackup }
    private var passphraseIsValid: Bool {
        !passphrase.isEmpty && passphrase == confirmedPassphrase
            && passphrase.precomposedStringWithCanonicalMapping.utf8.count <= JournalBackupProtection.maximumPassphraseBytes
    }

    var body: some View {
        List {
            Section {
                formatRow
                if let prepared {
                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.circle")
                    }
                    JournalCountsRows(counts: prepared.counts)
                } else if let exportError {
                    Label(exportError, systemImage: "exclamationmark.circle")
                    Button("Try Again") {
                        self.exportError = nil
                        preparation = UUID()
                    }
                } else {
                    ProgressView("Preparing Export…")
                }
            }
            if isBackup || isAndroidTransfer {
                Section {
                    Toggle("Protect with Passphrase", isOn: $protectsBackup)
                    if protectsBackup {
                        SecureField("Passphrase", text: $passphrase)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Confirm Passphrase", text: $confirmedPassphrase)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !confirmedPassphrase.isEmpty && passphrase != confirmedPassphrase {
                            Text("The passphrases don’t match.").foregroundStyle(.secondary)
                        } else if passphrase.precomposedStringWithCanonicalMapping.utf8.count > JournalBackupProtection.maximumPassphraseBytes {
                            Text("Choose a shorter passphrase.").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Protection")
                } footer: {
                    if protectsBackup {
                        Text("Keep your passphrase somewhere safe. You’ll need it to open this backup.")
                    } else {
                        Text("Anyone with the exported file can read its contents.")
                    }
                }
                .disabled(isProtecting)
                .onChange(of: protectsBackup) { enabled in
                    guard !enabled else { return }
                    passphrase = ""
                    confirmedPassphrase = ""
                }
            }
            Section {
                Text("Journal entries, notes and ratings")
                if isAndroidTransfer {
                    Text("Experience locations")
                    Text("Custom substances and custom units")
                } else if let pwJournalVersion {
                    Text("Experience locations and custom units")
                    if pwJournalVersion == .current {
                        Text("Unconfirmed entries and timeline visibility")
                    } else {
                        Text("Custom substance names, units and descriptions")
                    }
                } else {
                    Text("Locations saved on experiences and individual ingestions")
                    Text("Custom substances, units, formulations and overrides")
                }
                if isBackup {
                    Text("Routines, inventory and stock history")
                    Text("Journal preferences and integration settings")
                }
            } header: {
                Text("Included")
            } footer: {
                if isBackup {
                    Text("This backup contains private webhook addresses and leaderboard settings.")
                }
            }
            Section("Excluded") {
                if isBackup {
                    Text("Device state, including iCloud Sync and last unlock time")
                    Text("Assistant chats and API keys, cached references and retry records")
                    if isEyeOpen {
                        Text("Lab report PDFs attached to inventory")
                    }
                } else {
                    Text("App settings, webhooks and leaderboard history")
                    Text("Routines, inventory and stock history")
                    Text("Spray calculator data, assistant data and cached references")
                    if isAndroidTransfer {
                        Text("Unconfirmed entries, individual ingestion locations and timeline visibility")
                        Text("Formulation definitions and links, custom route overrides and advanced substance profiles")
                        Text("Mood and energy recorded on timed notes")
                    } else if let pwJournalVersion {
                        Text("Individual ingestion locations and administration sites")
                        Text("Formulations, route overrides and exact custom colors")
                        Text("Mood and energy recorded on timed notes")
                        if pwJournalVersion == .current {
                            Text("Standalone custom substance definitions and confirmation groups")
                            Text("Default routes on custom units")
                        } else {
                            Text("Unconfirmed entries")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isProtecting {
                    ProgressView().accessibilityLabel("Protecting Backup")
                } else {
                    Button("Save", action: save)
                        .disabled(prepared == nil || (requiresPassphrase && !passphraseIsValid))
                }
            }
        }
        .task(id: preparation) {
            guard prepared == nil else { return }
            do {
                let export = try await (isBackup ? viewModel.exportBackup() : viewModel.exportData(
                    forAndroid: isAndroidTransfer, pwJournalVersion: pwJournalVersion))
                if !Task.isCancelled { prepared = export }
            } catch {
                if !Task.isCancelled {
                    exportError = (error as? LocalizedError)?.errorDescription ?? "The export couldn’t be prepared."
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? (isBackup ? .freakLogBackup : .json),
            defaultFilename: exportDocument?.filename
        ) { result in
            if case .success = result {
                if isBackup { lastBackupTime = Date.now.timeIntervalSince1970 }
                toastViewModel.showSuccessToast(message: "Export Successful")
            } else {
                exportError = "The export couldn’t be saved."
            }
        }
    }

    private func save() {
        guard let prepared, !isProtecting else { return }
        exportError = nil
        if requiresPassphrase {
            guard passphraseIsValid else { return }
            isProtecting = true
            let secret = passphrase
            passphrase = ""
            confirmedPassphrase = ""
            Task {
                defer { isProtecting = false }
                do {
                    exportDocument = try await viewModel.protectBackup(
                        prepared.file, passphrase: secret, forAndroid: isAndroidTransfer)
                    isExporting = true
                } catch {
                    exportError = (error as? LocalizedError)?.errorDescription ?? "The backup couldn’t be protected."
                }
            }
        } else {
            exportDocument = prepared.file
            isExporting = true
        }
    }

    private var formatRow: some View {
        HStack(spacing: 12) {
            Image(systemName: isBackup ? "externaldrive" : "doc.text")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(formatName).font(.headline)
                Text(formatSubtitle)
                    .foregroundStyle(.secondary)
                if let prepared {
                    Text(prepared.file.data.count.formatted(.byteCount(style: .file)))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var formatSubtitle: String {
        if pwJournalVersion != nil { return "Journal transfer JSON" }
        if isAndroidTransfer { return "For FreakLog Android 11.36" }
        return isBackup ? "Restore in FreakLog" : "Portable journal data"
    }
}

#Preview {
    NavigationStack {
        SettingsContent(isFaceIDAvailable: true, viewModel: SettingsScreen.ViewModel())
    }
    .environmentObject(ToastViewModel())
}
