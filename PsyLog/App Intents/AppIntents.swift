import Foundation
import AppIntents

struct OpenLastExperienceIntent: AppIntent {

    static var title: LocalizedStringResource = "Open Last Experience"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.openLatestExperience()
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

struct SearchSubstancesIntent: AppIntent {

    static var title: LocalizedStringResource = "Search Substance"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.maybeSearchForSubstance()
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

struct AddIngestionIntent: AppIntent {

    static var title: LocalizedStringResource = "Add Ingestion"

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.addIngestion()
        return .result()
    }

    static var openAppWhenRun: Bool = true
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
    }

    static var shortcutTileColor: ShortcutTileColor = .blue
}
