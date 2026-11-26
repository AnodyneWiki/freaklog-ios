import Foundation
import AppIntents
import UniformTypeIdentifiers

struct OpenLastExperienceIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Last Experience"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.openLatestExperience()
        return .result()
    }

    static let openAppWhenRun: Bool = true
}

struct SearchSubstancesIntent: AppIntent {

    static let title: LocalizedStringResource = "Search Substance"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.maybeSearchForSubstance()
        return .result()
    }

    static let openAppWhenRun: Bool = true
}

struct AddIngestionIntent: AppIntent {

    static let title: LocalizedStringResource = "Add Ingestion"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.addIngestion()
        return .result()
    }

    static let openAppWhenRun: Bool = true
}

struct PrefillIngestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Prefill Ingestion"
    static let description = IntentDescription("Open an ingestion draft in FreakLog for review.")
    static let openAppWhenRun = true

    @Parameter(title: "Substance") var substance: String?
    @Parameter(title: "Route") var route: String?
    @Parameter(title: "Amount") var amount: Double?
    @Parameter(title: "Unit") var unit: String?
    @Parameter(title: "Time") var time: Date?
    @Parameter(title: "Note") var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let opened = Navigator.shared.prefillIngestion(
            IngestionPrefill(substance: substance, route: route, amount: amount, unit: unit, time: time, note: note)
        )
        let dialog: IntentDialog = opened
            ? "Review the ingestion in FreakLog."
            : "Finish or cancel your open ingestion draft before starting another."
        return .result(dialog: dialog)
    }
}

struct ExportJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Journal"
    static let description = IntentDescription("Return an unencrypted JSON file containing your journal entries and substance definitions.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        if #available(iOS 18.0, *) {
            try await requestConfirmation(dialog: "Export your journal as an unencrypted JSON file?")
        } else {
            try await requestConfirmation()
        }
        let export = try await SettingsScreen.ViewModel().exportData()
        let file = IntentFile(data: export.file.data, filename: export.file.filename + ".json", type: .json)
        return .result(value: file)
    }
}


struct JournalAutoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddIngestionIntent(),
                    phrases: [
                        "Add Ingestion in \(.applicationName)",
                        "New Ingestion in \(.applicationName)",
                        "Log Ingestion in \(.applicationName)",
                        "\(.applicationName) Ingestion",
                    ],
                    shortTitle: "Add Ingestion",
                    systemImageName: "plus"
        )
        AppShortcut(intent: OpenLastExperienceIntent(),
                    phrases: [
                        "Open Last Experience in \(.applicationName)",
                        "Open Experience in \(.applicationName)",
                        "Open Timeline in \(.applicationName)",
                    ],
                    shortTitle: "Open Last Experience",
                    systemImageName: "chart.xyaxis.line"
        )
        AppShortcut(intent: SearchSubstancesIntent(),
                    phrases: [
                        "Search Substances in \(.applicationName)",
                        "Search for Substance in \(.applicationName)",
                        "Search in \(.applicationName)",
                    ],
                    shortTitle: "Search Substance",
                    systemImageName: "magnifyingglass"
        )
        AppShortcut(intent: ExportJournalIntent(),
                    phrases: ["Export Journal in \(.applicationName)"],
                    shortTitle: "Export Journal",
                    systemImageName: "arrow.up.doc"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
