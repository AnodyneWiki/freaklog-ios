import AlertToast
import SwiftUI
import AppIntents

struct SettingsScreen: View {
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject var authenticator: Authenticator
    @EnvironmentObject private var toastViewModel: ToastViewModel

    var body: some View {
        SettingsContent(
            isFaceIDAvailable: authenticator.isFaceIDEnabled,
            isExporting: $viewModel.isExporting,
            exportedFile: viewModel.exportedFile,
            exportBackup: {
                viewModel.exportBackup()
            },
            exportData: {
                viewModel.exportData()
            },
            importFile: viewModel.importFile,
            deleteEverything: viewModel.deleteEverything
        )
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
    @State var isImporting = false
    @State private var removePublishedCopies = false
    @Binding var isExporting: Bool
    let exportedFile: ExportedFile
    @EnvironmentObject private var toastViewModel: ToastViewModel
    let exportBackup: () -> Void
    let exportData: () -> Void
    let importFile: (URL, Bool) -> Void
    let deleteEverything: () -> Void

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingImportAlert = false

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
                Section("UI") {
                    NavigationLink(value: GlobalNavigationDestination.journalSettings) {
                        Label("Journal", systemImage: "list.dash.header.rectangle")
                    }
                    NavigationLink(value: GlobalNavigationDestination.editColors) {
                        Label("Edit Substance Colors", systemImage: "paintpalette")
                    }
                    NavigationLink(value: GlobalNavigationDestination.customUnits) {
                        Label("Custom Units", systemImage: "pills")
                    }
                    NavigationLink(value: GlobalNavigationDestination.formulations) {
                        Label("Formulations", systemImage: "testtube.2")
                    }
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
                    NavigationLink(value: GlobalNavigationDestination.tabSettings) {
                        Label("Customize Tabs", systemImage: "rectangle.stack")
                    }
                }
            }
            Section(
                header: Text("Journal Data"),
                footer: Text("Use a FreakLog backup to restore your journal and settings in FreakLog. Backups include webhook addresses and leaderboard servers, so keep them private. Export JSON to share your journal with compatible apps. FreakLog can import both formats.")
            ) {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "externaldrive")
                }
                Button {
                    exportData()
                } label: {
                    Label("Export JSON", systemImage: "arrow.up.doc")
                }
                Button {
                    isShowingImportAlert.toggle()
                } label: {
                    Label("Import Data", systemImage: "arrow.down.doc")
                }
                .confirmationDialog(
                    "Replace Journal?",
                    isPresented: $isShowingImportAlert,
                    titleVisibility: .visible,
                    actions: {
                        Button("Import and Keep Published Copies", role: .destructive) {
                            removePublishedCopies = false
                            isImporting = true
                        }
                        Button("Import and Remove Discarded Copies", role: .destructive) {
                            removePublishedCopies = true
                            isImporting = true
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("Import replaces your local journal. A FreakLog backup also replaces settings. Portable JSON has no publication IDs, so it can republish entries on the next leaderboard sync if you keep their old copies.")
                    }
                )
                Button {
                    isShowingDeleteConfirmation.toggle()
                } label: {
                    Label("Delete Everything", systemImage: "trash").foregroundColor(.red)
                }
                .confirmationDialog(
                    "Delete Everything?",
                    isPresented: $isShowingDeleteConfirmation,
                    titleVisibility: .visible,
                    actions: {
                        Button("Delete", role: .destructive) {
                            deleteEverything()
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("This will delete all your experiences, ingestions, custom substances and sprays.")
                    }
                )
            }
            Section("Communication") {
                if isEyeOpen {
                    NavigationLink(value: GlobalNavigationDestination.faq) {
                        Label("Frequently Asked Questions", systemImage: "questionmark.square")
                    }
                    Link(destination: URL(string: repoUrl)!) {
                        Label("Source Code", systemImage: "doc.text.magnifyingglass")
                    }
                    Link(destination: URL(string: communityUrl)!) {
                        Label("Join Community or Report Issue", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Button {} label: {
                        Label("Get beta updates", systemImage: "square.and.arrow.down.on.square")
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .tint(Color(uiColor: .secondaryLabel))
                    .disabled(true)
                    .accessibilityHint("No public beta is currently available.")
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ExportedFile.readableContentTypes
        ) { result in
            do {
                importFile(try result.get(), removePublishedCopies)
            } catch {
                toastViewModel.showErrorToast(message: "Import Failed")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportedFile,
            contentType: exportedFile.contentType,
            defaultFilename: exportedFile.filename
        ) { result in
            if case .success = result {
                toastViewModel.showSuccessToast(message: "Export Successful")
            } else {
                toastViewModel.showErrorToast(message: "Export Failed")
            }
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

#Preview {
    SettingsContent(
        isFaceIDAvailable: true,
        isImporting: false,
        isExporting: .constant(false),
        exportedFile: ExportedFile(),
        exportBackup: {},
        exportData: {},
        importFile: { _, _ in },
        deleteEverything: {}
    )
    .accentColor(Color.blue)
}
