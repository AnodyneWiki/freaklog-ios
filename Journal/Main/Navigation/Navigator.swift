import SwiftUI

class Navigator: ObservableObject {

    static let shared = Navigator()

    @Published var statsTabPath = NavigationPath()
    @Published var journalTabPath = NavigationPath()
    @Published var substancesTabPath = NavigationPath()
    @Published var saferTabPath = NavigationPath()
    @Published var settingsTabPath = NavigationPath()

    @Published var isShowingAddIngestionSheet = false

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

    var binding: Binding<Tab> {
        Binding {
            self.selectedTab
        } set: { newValue in
            if self.selectedTab == newValue {
                switch newValue {
                case .stats:
                    if !self.statsTabPath.isEmpty {
                        self.statsTabPath.removeLast()
                    }
                case .journal:
                    if !self.journalTabPath.isEmpty {
                        self.journalTabPath.removeLast()
                    } else {
                        self.journalSearchText = ""
                        self.isFavoriteFilterEnabled = false
                        self.isJournalSearchFocused = true
                    }
                case .substances:
                    if !self.substancesTabPath.isEmpty {
                        self.substancesTabPath.removeLast()
                    } else {
                        self.substanceSearchText = ""
                        self.clearCategories()
                        self.isSubstanceSearchFocused = true
                    }
                case .safer:
                    if !self.saferTabPath.isEmpty {
                        self.saferTabPath.removeLast()
                    }
                case .settings:
                    if !self.settingsTabPath.isEmpty {
                        self.settingsTabPath.removeLast()
                    }
                }
            }
            self.selectedTab = newValue
        }
    }

    func openLatestActiveExperience() {
        selectedTab = .journal
        if let latestActiveExperience = PersistenceController.shared.getLatestActiveExperience() {
            journalTabPath.removeLast(journalTabPath.count)
            journalTabPath.append(GlobalNavigationDestination.experience(experience: latestActiveExperience))
        }
    }

    func openLatestExperience() {
        selectedTab = .journal
        if let latestExperience = PersistenceController.shared.getLatestExperience() {
            journalTabPath.removeLast(journalTabPath.count)
            journalTabPath.append(GlobalNavigationDestination.experience(experience: latestExperience))
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

    func showAddIngestionFullScreenCover() {
        isShowingAddIngestionSheet.toggle()
    }
}
