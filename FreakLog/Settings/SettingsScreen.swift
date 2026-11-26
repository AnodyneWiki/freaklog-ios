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
            }
            if isEyeOpen {
                Section("Communication") {
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
                    NavigationLink {
                        SaferScreen()
                    } label: {
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

private struct JournalDataSettings: View {
    @ObservedObject var viewModel: SettingsScreen.ViewModel
    @AppStorage(PersistenceController.isICloudSyncEnabledKey) private var isICloudSyncEnabled = false
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @State private var isImporting = false
    @State private var removePublishedCopies = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingImportAlert = false

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
            } footer: {
                Text("Sync your journal across devices using iCloud.")
            }
            Section(
                header: Text("Journal Data"),
                footer: Text("Use a FreakLog backup to restore your journal and settings in FreakLog. Backups include webhook addresses and leaderboard servers, so keep them private. Export JSON to share your journal with compatible apps. FreakLog can import both formats.")
            ) {
                Button {
                    viewModel.exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "externaldrive")
                }
                Button {
                    viewModel.exportData()
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
                            viewModel.deleteEverything()
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("This will delete all your experiences, ingestions, custom substances and sprays.")
                    }
                )
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ExportedFile.readableContentTypes
        ) { result in
            do {
                viewModel.importFile(try result.get(), removePublishedCopies: removePublishedCopies)
            } catch {
                toastViewModel.showErrorToast(message: "Import Failed")
            }
        }
        .fileExporter(
            isPresented: $viewModel.isExporting,
            document: viewModel.exportedFile,
            contentType: viewModel.exportedFile.contentType,
            defaultFilename: viewModel.exportedFile.filename
        ) { result in
            if case .success = result {
                toastViewModel.showSuccessToast(message: "Export Successful")
            } else {
                toastViewModel.showErrorToast(message: "Export Failed")
            }
        }
        .navigationTitle("Journal Data")
    }
}

#Preview {
    SettingsContent(isFaceIDAvailable: true, viewModel: SettingsScreen.ViewModel())
}
