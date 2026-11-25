import SwiftUI

class Navigator: ObservableObject {

    @MainActor static let shared = Navigator()

    @Published var statsTabPath = NavigationPath()
    @Published var journalTabPath = NavigationPath()
    @Published var substancesTabPath = NavigationPath()
    @Published var toolsTabPath = NavigationPath()
    @Published var settingsTabPath = NavigationPath()

    @Published var isShowingAddIngestionSheet = false {
        didSet {
            if !isShowingAddIngestionSheet {
                ingestionPrefill = nil
            }
        }
    }
    // The time a new ingestion starts at, handed to the add ingestion screens; nil is now
    @Published private(set) var addIngestionStartTime: Date?
    @Published private(set) var ingestionPrefill: IngestionPrefill?

    @Published var selectedTab: Tab = .journal

    @Published var isSubstanceSearchFocused = false
    @Published var substanceSearchText = ""
    @Published var isSearchingAnodyneWiki = false
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
        case .tools: \.toolsTabPath
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

    // The info page of a substance by its stored name, nil for a custom substance that no longer exists
    static func substanceInfoDestination(for substanceName: String) -> GlobalNavigationDestination? {
        if let substance = SubstanceRepo.shared.getSubstance(name: substanceName) {
            return .substance(substance: substance)
        }
        return PersistenceController.shared.getCustomSubstance(name: substanceName).map { .customSubstance(customSubstance: $0) }
    }

    // Opens on top of the current tab, where the swipe or tap asking for it happened
    func openInCurrentTab(_ destination: GlobalNavigationDestination) {
        self[keyPath: Self.pathKeyPath(for: selectedTab)].append(destination)
    }

    func maybeSearchForSubstance() {
        selectedTab = .substances
        let isEyeOpen = UserDefaults.standard.bool(forKey: PersistenceController.isEyeOpenKey2)
        if isEyeOpen {
            substancesTabPath.removeLast(substancesTabPath.count)
            clearCategories()
            substanceSearchText = ""
            isSearchingAnodyneWiki = false
            isSubstanceSearchFocused = true
        }
    }

    func addIngestion() {
        selectedTab = .journal
        journalTabPath.removeLast(journalTabPath.count)
        showAddIngestionFullScreenCover()
    }

    func showAddIngestionFullScreenCover(startingAt startTime: Date? = nil) {
        guard !isShowingAddIngestionSheet else { return }
        ingestionPrefill = nil
        addIngestionStartTime = startTime
        isShowingAddIngestionSheet = true
    }

    func prefillIngestion(_ prefill: IngestionPrefill) -> Bool {
        guard !isShowingAddIngestionSheet else { return false }
        selectedTab = .journal
        journalTabPath.removeLast(journalTabPath.count)
        ingestionPrefill = prefill
        addIngestionStartTime = prefill.time
        isShowingAddIngestionSheet = true
        return true
    }
}

private struct AddIngestionStartTimeKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

private struct IngestionPrefillNoteKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var addIngestionStartTime: Date? {
        get { self[AddIngestionStartTimeKey.self] }
        set { self[AddIngestionStartTimeKey.self] = newValue }
    }

    var ingestionPrefillNote: String? {
        get { self[IngestionPrefillNoteKey.self] }
        set { self[IngestionPrefillNoteKey.self] = newValue }
    }
}
