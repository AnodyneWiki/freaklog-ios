import SwiftUI

class Navigator: ObservableObject {

    @MainActor static let shared = Navigator()

    @Published var statsTabPath = NavigationPath()
    @Published var journalTabPath = NavigationPath()
    @Published var substancesTabPath = NavigationPath()
    @Published var saferTabPath = NavigationPath()
    @Published var settingsTabPath = NavigationPath()

    @Published var isShowingAddIngestionSheet = false
    // The time a new ingestion starts at, handed to the add ingestion screens; nil is now
    @Published private(set) var addIngestionStartTime: Date?

    @Published var selectedTab: Tab = .journal

    @Published var isSubstanceSearchFocused = false
    @Published var substanceSearchText = ""
    @Published var selectedCategories: [String] = []

    @Published var isJournalSearchFocused = false
    @Published var isFavoriteFilterEnabled = false
    @Published var journalSearchText = ""

    func clearCategories() {
        selectedCategories.removeAll()
    }

    static func pathKeyPath(for tab: Tab) -> ReferenceWritableKeyPath<Navigator, NavigationPath> {
        switch tab {
        case .stats: \.statsTabPath
        case .journal: \.journalTabPath
        case .substances: \.substancesTabPath
        case .safer: \.saferTabPath
        case .settings: \.settingsTabPath
        }
    }

    // Tapping the selected tab again goes back one screen, or on the tab's root resets and focuses its search
    @MainActor
    var binding: Binding<Tab> {
        Binding {
            self.selectedTab
        } set: { newValue in
            if self.selectedTab == newValue {
                let path = Self.pathKeyPath(for: newValue)
                if !self[keyPath: path].isEmpty {
                    self[keyPath: path].removeLast()
                } else if newValue == .journal {
                    self.journalSearchText = ""
                    self.isFavoriteFilterEnabled = false
                    self.isJournalSearchFocused = true
                } else if newValue == .substances {
                    self.substanceSearchText = ""
                    self.clearCategories()
                    self.isSubstanceSearchFocused = true
                }
            }
            self.selectedTab = newValue
        }
    }

    func openLatestActiveExperience() {
        openInJournal(PersistenceController.shared.getLatestActiveExperience())
    }

    func openLatestExperience() {
        openInJournal(PersistenceController.shared.getLatestExperience())
    }

    private func openInJournal(_ experience: Experience?) {
        selectedTab = .journal
        if let experience {
            journalTabPath.removeLast(journalTabPath.count)
            journalTabPath.append(GlobalNavigationDestination.experience(experience: experience))
        }
    }

    func maybeSearchForSubstance() {
        selectedTab = .substances
        let isEyeOpen = UserDefaults.standard.bool(forKey: PersistenceController.isEyeOpenKey2)
        if isEyeOpen {
            substancesTabPath.removeLast(substancesTabPath.count)
            clearCategories()
            substanceSearchText = ""
            isSubstanceSearchFocused = true
        }
    }

    func addIngestion() {
        selectedTab = .journal
        journalTabPath.removeLast(journalTabPath.count)
        showAddIngestionFullScreenCover()
    }

    func showAddIngestionFullScreenCover(startingAt startTime: Date? = nil) {
        addIngestionStartTime = startTime
        isShowingAddIngestionSheet.toggle()
    }
}

private struct AddIngestionStartTimeKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var addIngestionStartTime: Date? {
        get { self[AddIngestionStartTimeKey.self] }
        set { self[AddIngestionStartTimeKey.self] = newValue }
    }
}
