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
    @Published private(set) var addIngestionEndTime: Date?
    @Published private(set) var ingestionPrefill: IngestionPrefill?

    @Published var selectedTab: Tab = .journal

    @Published var isSubstanceSearchFocused = false
    @Published var substanceSearchText = ""
    @Published var substanceSearchScope = UnifiedSearchScope.library

    @Published var isFavoriteFilterEnabled = false

    static func pathKeyPath(for tab: Tab) -> ReferenceWritableKeyPath<Navigator, NavigationPath> {
        switch tab {
        case .stats: \.statsTabPath
        case .journal: \.journalTabPath
        case .substances: \.substancesTabPath
        case .tools: \.toolsTabPath
        case .settings: \.settingsTabPath
        }
    }

    // Preserve the navigation stack and search when reselecting a tab.
    @MainActor
    var binding: Binding<Tab> {
        Binding {
            self.selectedTab
        } set: { newValue in
            self.selectedTab = newValue
        }
    }

    func openLatestActiveExperience() {
        openInJournal(PersistenceController.shared.getLatestActiveExperience())
    }

    func openLatestExperience() {
        openInJournal(PersistenceController.shared.getLatestExperience())
    }

    func openActivityExperience(at uri: URL) {
        let context = PersistenceController.shared.viewContext
        let experience = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri).flatMap {
            (try? context.existingObject(with: $0) as? Experience).flatMap { $0.isDeleted ? nil : $0 }
        }
        journalTabPath = NavigationPath()
        openInJournal(experience)
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
        let bundled = SubstanceRepo.shared.getSubstance(name: substanceName)
        if let bundled, bundled.usesWikiReferences {
            return .substance(substance: bundled)
        }
        if let custom = PersistenceController.shared.getCustomSubstance(name: substanceName) {
            return .customSubstance(customSubstance: custom)
        }
        return bundled.map { .substance(substance: $0) }
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
            substanceSearchText = ""
            substanceSearchScope = .library
            isSubstanceSearchFocused = true
        }
    }

    func addIngestion() {
        selectedTab = .journal
        journalTabPath.removeLast(journalTabPath.count)
        showAddIngestionFullScreenCover()
    }

    func showAddIngestionFullScreenCover(startingAt startTime: Date? = nil, endingAt endTime: Date? = nil) {
        guard !isShowingAddIngestionSheet else { return }
        ingestionPrefill = nil
        addIngestionStartTime = startTime
        addIngestionEndTime = endTime
        isShowingAddIngestionSheet = true
    }

    func prefillIngestion(_ prefill: IngestionPrefill) -> Bool {
        guard !isShowingAddIngestionSheet else { return false }
        selectedTab = .journal
        journalTabPath.removeLast(journalTabPath.count)
        ingestionPrefill = prefill
        addIngestionStartTime = prefill.time
        addIngestionEndTime = nil
        isShowingAddIngestionSheet = true
        return true
    }
}

private struct AddIngestionStartTimeKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

private struct AddIngestionEndTimeKey: EnvironmentKey {
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

    var addIngestionEndTime: Date? {
        get { self[AddIngestionEndTimeKey.self] }
        set { self[AddIngestionEndTimeKey.self] = newValue }
    }

    var ingestionPrefillNote: String? {
        get { self[IngestionPrefillNoteKey.self] }
        set { self[IngestionPrefillNoteKey.self] = newValue }
    }
}
