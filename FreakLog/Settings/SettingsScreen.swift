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
            journalFile: viewModel.journalFile,
            exportData: {
                viewModel.exportData()
            },
            importData: { data in
                viewModel.importData(data: data)
            },
            deleteEverything: {
                Task {
                    viewModel.deleteEverything()
                    await WebhookManager.shared.deleteAllPresetsAndMessages()
                }
            }
        )
        .onAppear {
            viewModel.toastViewModel = toastViewModel
        }
    }
}

struct SettingsContent: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.hasToUnlockAppKey) var hasToUnlockApp: Bool = false
    @AppStorage(PersistenceController.lockTimeOptionKey) var lockTimeOption: LockTimeOption = .after5Minutes
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity = true
    // PersistenceController reads this with bool(forKey:), so unset means off
    @AppStorage(PersistenceController.isICloudSyncEnabledKey) var isICloudSyncEnabled: Bool = false
    let isFaceIDAvailable: Bool
    @State var isImporting = false
    @Binding var isExporting: Bool
    let journalFile: JournalFile
    @EnvironmentObject private var toastViewModel: ToastViewModel
    let exportData: () -> Void
    let importData: (Data) -> Void
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
                Toggle("iCloud Sync", isOn: $isICloudSyncEnabled.animation()).tint(Color.accentColor)
                    .onChange(of: isICloudSyncEnabled) { newValue in
                        PersistenceController.shared.updateCloudKitSyncStatus(newValue)
                    }
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
                    NavigationLink(value: GlobalNavigationDestination.leaderboardServers) {
                        Label("Leaderboard", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink(value: GlobalNavigationDestination.tabSettings) {
                        Label("Customize Tabs", systemImage: "rectangle.stack")
                    }
                    Group {
                        Toggle("Dosage dots", isOn: $isHidingDosageDots.inverted)
                        Toggle("Tolerance chart", isOn: $isHidingToleranceChartInExperience.inverted)
                        Toggle("Substance info", isOn: $isHidingSubstanceInfoInExperience.inverted)
                        if LiveActivities.areAvailable {
                            Toggle("Automatic live activities", isOn: $shouldAutomaticallyStartLiveActivity)
                        }
                    }.tint(.accentColor)
                }
            }
            Section(
                header: Text("Journal Data"),
                footer: Text("You can export all your data into a file on your phone and import it again at a later time. This way you can migrate your data to Android or delete the app without losing your data.")
            ) {
                Button {
                    exportData()
                } label: {
                    Label("Export Data", systemImage: "arrow.up.doc")
                }
                Button {
                    isShowingImportAlert.toggle()
                } label: {
                    Label("Import Data", systemImage: "arrow.down.doc")
                }
                .confirmationDialog(
                    "Are you sure?",
                    isPresented: $isShowingImportAlert,
                    titleVisibility: .visible,
                    actions: {
                        Button("Import", role: .destructive) {
                            isImporting.toggle()
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("Importing will delete all the data currently in the app and replace it with the imported data.")
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
                    Link(destination: URL(string: testflightUrl)!) {
                        Label("Get beta updates", systemImage: "square.and.arrow.down.on.square")
                    }
                    Link(destination: URL(string: communityUrl)!) {
                        Label("Join the community", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Link(destination: URL(string: supportUrl)!) {
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let selectedFile: URL = try result.get()
                if selectedFile.startAccessingSecurityScopedResource() {
                    let data = try Data(contentsOf: selectedFile)
                    importData(data)
                } else {
                    toastViewModel.showErrorToast(message: "Permission Denied")
                }
                selectedFile.stopAccessingSecurityScopedResource()
            } catch {
                toastViewModel.showErrorToast(message: "Import Failed")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: journalFile,
            contentType: .json,
            defaultFilename: "\(appName) \(Date().ISO8601Format(.iso8601(timeZone: TimeZone.current, dateSeparator: .dash, dateTimeSeparator: .standard, timeSeparator: .omitted)))"
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
        journalFile: JournalFile(experiences: [], customSubstances: [], customUnits: []),
        exportData: {},
        importData: { _ in },
        deleteEverything: {}
    )
    .accentColor(Color.blue)
}
