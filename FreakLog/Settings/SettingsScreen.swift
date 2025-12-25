import AlertToast
import SwiftUI
import AppIntents

struct SettingsScreen: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(Authenticator.hasToUnlockKey) var hasToUnlockApp: Bool = false
    @AppStorage(Authenticator.lockTimeOptionKey) var lockTimeOptionString: String = LockTimeOption.after5Minutes.rawValue
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(PersistenceController.isICloudSyncEnabledKey) var isICloudSyncEnabled: Bool = true
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject var authenticator: Authenticator

    private var lockTimeOption: LockTimeOption {
        LockTimeOption(rawValue: lockTimeOptionString) ?? LockTimeOption.after5Minutes
    }

    private func setLockTimeOption(option: LockTimeOption) {
        lockTimeOptionString = option.rawValue
    }
    
    private var fabButtonPosition: FabButtonPosition {
        FabButtonPosition(rawValue: fabButtonPositionString) ?? .center
    }

    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPositionString: String = FabButtonPosition.center.rawValue

    var body: some View {
        let timeOptionBinding = Binding {
            lockTimeOption
        } set: { newValue in
            setLockTimeOption(option: newValue)
        }
        
        SettingsContent(
            isEyeOpen: $isEyeOpen,
            isHidingDosageDots: $isHidingDosageDots,
            isHidingToleranceChartInExperience: $isHidingToleranceChartInExperience,
            isHidingSubstanceInfoInExperience: $isHidingSubstanceInfoInExperience,
            areRedosesDrawnIndividually: $areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: $areSubstanceHeightsIndependent,
            shouldAutomaticallyStartLiveActivity: $shouldAutomaticallyStartLiveActivity,
            isICloudSyncEnabled: $isICloudSyncEnabled,
            isFaceIDAvailable: authenticator.isFaceIDEnabled,
            hasToUnlockApp: $hasToUnlockApp,
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
            },
            isShowingToast: $viewModel.isShowingToast,
            isSuccessToast: $viewModel.isShowingSuccessToast,
            toastMessage: $viewModel.toastMessage,
            lockTimeOption: timeOptionBinding
        )
    }
}

struct SettingsContent: View {
    @Binding var isEyeOpen: Bool
    @Binding var isHidingDosageDots: Bool
    @Binding var isHidingToleranceChartInExperience: Bool
    @Binding var isHidingSubstanceInfoInExperience: Bool
    @Binding var areRedosesDrawnIndividually: Bool
    @Binding var areSubstanceHeightsIndependent: Bool
    @Binding var shouldAutomaticallyStartLiveActivity: Bool
    @Binding var isICloudSyncEnabled: Bool
    let isFaceIDAvailable: Bool
    @Binding var hasToUnlockApp: Bool
    @State var isImporting = false
    @Binding var isExporting: Bool
    let journalFile: JournalFile
    @EnvironmentObject private var toastViewModel: ToastViewModel
    let exportData: () -> Void
    let importData: (Data) -> Void
    let deleteEverything: () -> Void
    @Binding var isShowingToast: Bool
    @Binding var isSuccessToast: Bool
    @Binding var toastMessage: String
    @Binding var lockTimeOption: LockTimeOption

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
                    NavigationLink(value: GlobalNavigationDestination.webhookSettings) {
                        Label("Webhooks", systemImage: "network")
                    }
                    NavigationLink(value: GlobalNavigationDestination.tabSettings) {
                        Label("Customize Tabs", systemImage: "rectangle.stack")
                    }
                    Group {
                        Toggle("Hide dosage dots", isOn: $isHidingDosageDots)
                        Toggle("Hide tolerance chart", isOn: $isHidingToleranceChartInExperience)
                        Toggle("Hide substance info", isOn: $isHidingSubstanceInfoInExperience)
                        Toggle("Draw redoses individually", isOn: $areRedosesDrawnIndividually)
                        Toggle("Independent substance heights", isOn: $areSubstanceHeightsIndependent)
                        if #available(iOS 16.2, *) {
                            if !ProcessInfo.processInfo.isiOSAppOnMac, ActivityManager.shared.authorizationInfo.areActivitiesEnabled {
                                Toggle("Automatic live activities", isOn: $shouldAutomaticallyStartLiveActivity)
                            }
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
                // print("Error getting data: \(error.localizedDescription)") // Removed debug print
                // better: Just ignore, or handle error properly without console spam

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
        .toast(isPresenting: $isShowingToast) {
            AlertToast(
                displayMode: .alert,
                type: isSuccessToast ? .complete(.green) : .error(.red),
                title: toastMessage
            )
        }
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
        isEyeOpen: .constant(true),
        isHidingDosageDots: .constant(false),
        isHidingToleranceChartInExperience: .constant(false),
        isHidingSubstanceInfoInExperience: .constant(false),
        areRedosesDrawnIndividually: .constant(false),
        areSubstanceHeightsIndependent: .constant(false),
        shouldAutomaticallyStartLiveActivity: .constant(false),
        isICloudSyncEnabled: .constant(true),
        isFaceIDAvailable: true,
        hasToUnlockApp: .constant(false),
        isImporting: false,
        isExporting: .constant(false),
        journalFile: JournalFile(experiences: [], customSubstances: [], customUnits: []),
        exportData: {},
        importData: { _ in },
        deleteEverything: {},
        isShowingToast: .constant(false),
        isSuccessToast: .constant(false),
        toastMessage: .constant(""),
        lockTimeOption: .constant(.after5Minutes)
    )
    .accentColor(Color.blue)
}
