import AlertToast
import SwiftUI
import AppIntents

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
    @AppStorage(PersistenceController.hasToUnlockAppKey) var hasToUnlockApp: Bool = false
    @AppStorage(PersistenceController.lockTimeOptionKey) var lockTimeOption: LockTimeOption = .after5Minutes
    // PersistenceController reads this with bool(forKey:), so unset means off
    @AppStorage(PersistenceController.isICloudSyncEnabledKey) var isICloudSyncEnabled: Bool = false
    let isFaceIDAvailable: Bool
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @EnvironmentObject private var toastViewModel: ToastViewModel

    var body: some View {
        List {
            Section(
                header: Text("Privacy"),
                footer: Text("Turn on to sync your data across your devices.")
            ) {
                if isFaceIDAvailable {
                    Toggle("Require App Unlock", isOn: $hasToUnlockApp.animation()).tint(Color.accentColor)
                } else {
                    Text("Enable Face ID for Journal in settings to lock the app.")
                }
                if hasToUnlockApp {
                    Picker("Time option", selection: $lockTimeOption) {
                        ForEach(LockTimeOption.allCases) { option in
                            Text(option.text)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Toggle("iCloud Sync", isOn: Binding(get: { isICloudSyncEnabled }, set: { enabled in
                    do {
                        try PersistenceController.shared.updateCloudKitSyncStatus(enabled)
                    } catch {
                        toastViewModel.showErrorToast(message: "Couldn't Change iCloud Sync")
                    }
                })).tint(Color.accentColor)
            }
            if isEyeOpen {
                Section("Appearance") {
                    NavigationLink(value: GlobalNavigationDestination.journalSettings) {
                        Label("Journal", systemImage: "list.dash.header.rectangle")
                    }
                    NavigationLink(value: GlobalNavigationDestination.editColors) {
                        Label("Edit Substance Colors", systemImage: "paintpalette")
                    }
                    NavigationLink(value: GlobalNavigationDestination.tabSettings) {
                        Label("Customize Tabs", systemImage: "rectangle.stack")
                    }
                }
            }
            Section {
                NavigationLink {
                    JournalDataSettings(viewModel: viewModel)
                } label: {
                    Label("Journal Data", systemImage: "externaldrive")
                }
            }
            if isEyeOpen {
                Section("Logging") {
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
            if isEyeOpen {
                Section("Communication") {
                    NavigationLink(value: GlobalNavigationDestination.faq) {
                        Label("Frequently Asked Questions", systemImage: "questionmark.square")
                    }
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
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(getCurrentAppVersion())
                        .foregroundColor(.secondary)
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

private struct JournalDataSettings: View {
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @State private var isChoosingFile = false
    @State private var isConfirmingDeletion = false

    var body: some View {
        List {
            Section("Restore") {
                if let error = viewModel.importError, viewModel.importReview == nil {
                    Label(error, systemImage: "exclamationmark.circle")
                }
                Button {
                    viewModel.importError = nil
                    isChoosingFile = true
                } label: {
                    if viewModel.isPreparingImport {
                        ProgressView("Reading File…")
                    } else {
                        Label("Import Data", systemImage: "arrow.down.doc")
                    }
                }
                .disabled(viewModel.isPreparingImport)
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
                            Text("For compatible apps").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete Everything", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Journal Data")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ExportedFile.readableContentTypes) { result in
            switch result {
            case .success(let url): viewModel.prepareImport(url)
            case .failure: viewModel.importError = "The file couldn’t be opened. Choose it again to retry."
            }
        }
        .sheet(item: $viewModel.importReview, onDismiss: { viewModel.importError = nil }) { review in
            JournalImportReview(review: review, viewModel: viewModel)
        }
        .confirmationDialog("Delete Everything?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: viewModel.deleteEverything)
        } message: {
            Text("This will delete all your experiences, ingestions, custom substances and sprays.")
        }
    }
}

private struct JournalImportReview: View {
    let review: SettingsScreen.ImportReview
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var removePublishedCopies = false
    @State private var isConfirmingReplacement = false

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    LabeledContent("Format", value: review.isBackup ? "FreakLog Backup" : "Journal JSON")
                    LabeledContent("Name", value: review.filename)
                }
                Section("Incoming Journal") {
                    JournalCountsRows(counts: review.counts)
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
                } footer: {
                    Text(review.isBackup
                         ? "Restoring this backup replaces your current journal and backed-up settings."
                         : "Importing this file replaces your current journal.")
                }
            }
            .disabled(viewModel.isApplyingImport)
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isApplyingImport)
                }
            }
            .confirmationDialog("Replace Journal?", isPresented: $isConfirmingReplacement, titleVisibility: .visible) {
                Button("Replace Journal", role: .destructive) {
                    viewModel.importFile(review, removePublishedCopies: removePublishedCopies)
                }
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
    }
}

private struct JournalExportReview: View {
    let viewModel: SettingsScreen.ViewModel
    @EnvironmentObject private var toastViewModel: ToastViewModel
    let isBackup: Bool
    @State private var preparation = UUID()
    @State private var prepared: SettingsScreen.PreparedExport?
    @State private var exportError: String?
    @State private var isExporting = false

    private var formatName: String { isBackup ? "FreakLog Backup" : "Journal JSON" }

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
            Section {
                Text("Journal entries, notes and ratings")
                Text("Locations saved on experiences and individual ingestions")
                Text("Custom substances, units, formulations and overrides")
                if isBackup {
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
                } else {
                    Text("App settings, webhooks and leaderboard history")
                    Text("Spray calculator data, assistant data and cached references")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    exportError = nil
                    isExporting = true
                }
                .disabled(prepared == nil)
            }
        }
        .task(id: preparation) {
            guard prepared == nil else { return }
            do {
                let export = try await (isBackup ? viewModel.exportBackup() : viewModel.exportData())
                if !Task.isCancelled { prepared = export }
            } catch {
                if !Task.isCancelled {
                    exportError = (error as? LocalizedError)?.errorDescription ?? "The export couldn’t be prepared."
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: prepared?.file,
            contentType: prepared?.file.contentType ?? (isBackup ? .freakLogBackup : .json),
            defaultFilename: prepared?.file.filename
        ) { result in
            if case .success = result {
                toastViewModel.showSuccessToast(message: "Export Successful")
            } else {
                exportError = "The export couldn’t be saved."
            }
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
                Text(isBackup ? "Restore in FreakLog" : "For compatible apps")
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
}

#Preview {
    NavigationStack {
        SettingsContent(isFaceIDAvailable: true, viewModel: SettingsScreen.ViewModel())
    }
    .environmentObject(ToastViewModel())
}
