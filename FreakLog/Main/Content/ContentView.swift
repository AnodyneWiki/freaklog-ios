import AlertToast
import SwiftUI
import StoreKit
import CoreData

struct ContentView: View {
    @AppStorage(PersistenceController.needsToSeeWelcomeKey) var needsToSeeWelcome: Bool = true
    @AppStorage(PersistenceController.isEyeOpenKey1) var isEyeOpen1: Bool = false
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen2: Bool = false
    @AppStorage("hasBeenMigrated2") var hasBeenMigrated2: Bool = false
    @AppStorage("hasBeenMigrated3") var hasBeenMigrated3: Bool = false
    @AppStorage("hasBeenMigrated4") var hasBeenMigrated4: Bool = false
    @AppStorage("hasBeenMigrated5") var hasBeenMigrated5: Bool = false
    @AppStorage("hasBeenMigrated6") var hasBeenMigrated6: Bool = false
    @AppStorage("hasBeenMigrated7") var hasBeenMigrated7: Bool = false

    var body: some View {
        ContentScreen(isEyeOpen: isEyeOpen2)
            .fullScreenCover(isPresented: $needsToSeeWelcome) {
                WelcomeScreen(isShowingWelcome: $needsToSeeWelcome)
            }
            .onAppear {
                if !hasBeenMigrated2 {
                    PersistenceController.shared.migrateCompanionsAndExperienceSortDates()
                    hasBeenMigrated2 = true
                    isEyeOpen2 = isEyeOpen1
                }
                if !hasBeenMigrated3 {
                    PersistenceController.shared.migrateIngestionNamesAndUnits()
                    hasBeenMigrated3 = true
                }
                if !hasBeenMigrated4 {
                    PersistenceController.shared.migrateColors()
                    hasBeenMigrated4 = true
                }
                if !hasBeenMigrated5 {
                    PersistenceController.shared.migrateBenzydamineUnits()
                    hasBeenMigrated5 = true
                }
                if !hasBeenMigrated6 {
                    PersistenceController.shared.migrateCannabisAndMushroomUnits()
                    hasBeenMigrated6 = true
                }
                if !hasBeenMigrated7 {
                    PersistenceController.shared.migrateRemoveDuplicateCompanions()
                    hasBeenMigrated7 = true
                }
            }
    }
}

struct ContentScreen: View {
    let isEyeOpen: Bool

    @ObservedObject var navigator = Navigator.shared
    @ObservedObject var tabManager = TabManager.shared
    @FocusState var isSearchFocused: Bool
    @EnvironmentObject var authenticator: Authenticator

    var body: some View {
        Group {
            TabView(selection: navigator.binding) {
                ForEach(filteredTabs) { tab in
                    view(for: tab)
                }
            }
            .onOpenURL { url in
                if url.absoluteString == openLatestExperience {
                    navigator.openLatestActiveExperience()
                }
            }
            .onChange(of: filteredTabs) { _ in
                if !filteredTabs.contains(navigator.selectedTab) {
                    if let firstTab = filteredTabs.first {
                        navigator.selectedTab = firstTab
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $navigator.isShowingAddIngestionSheet, onDismiss: {
            UserDefaults.standard.set(nil, forKey: PersistenceController.lastIngestionTimeOfExperienceWhereAddIngestionTappedKey)
            UserDefaults.standard.set(nil, forKey: PersistenceController.clonedIngestionTimeKey)
            maybeRequestAppRating()
        }) {
            AuthenticatorWrapper(authenticator: authenticator) {
                ChooseSubstanceScreen()
            }
        }
    }

    var filteredTabs: [Tab] {
        let baseTabs = tabManager.enabledTabs
        
        return baseTabs.filter { tab in
            isEyeOpen || (tab != .substances && tab != .safer)
        }
    }

    @ViewBuilder
    func view(for tab: Tab) -> some View {
        switch tab {
        case .stats:
            statsTab
        case .journal:
            journalTab
        case .substances:
            substancesTab
        case .safer:
            saferTab
        case .settings:
            settingsTab
        }
    }

    @AppStorage("openUntilRatedCount") var openUntilRatedCount: Int = 0

    private func maybeRequestAppRating() {
        if #available(iOS 16.2, *) {
            if openUntilRatedCount < 10 {
                openUntilRatedCount += 1
            } else if openUntilRatedCount == 10 {
                let ingestionFetchRequest = Ingestion.fetchRequest()
                let allIngestions = (try? PersistenceController.shared.viewContext.fetch(ingestionFetchRequest)) ?? []
                if isEyeOpen && allIngestions.count > 10 {
                    if let windowScene = UIApplication.shared.currentWindow?.windowScene {
                        SKStoreReviewController.requestReview(in: windowScene)
                    }
                    openUntilRatedCount += 1
                }
            }
        }
    }

    var statsTab: some View {
        NavigationStack(path: $navigator.statsTabPath) {
            StatsScreen()
                .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                    getScreen(from: destination)
                }
        }
        .tabItem {
            Label("Stats", systemImage: "chart.bar")
        }
        .tag(Tab.stats)
    }

    var journalTab: some View {
        NavigationStack(path: $navigator.journalTabPath) {
            JournalScreen(
                searchText: $navigator.journalSearchText,
                isSearchPresented: $navigator.isJournalSearchFocused,
                isFavoriteFilterEnabled: $navigator.isFavoriteFilterEnabled
            ).navigationDestination(for: GlobalNavigationDestination.self) { destination in
                getScreen(from: destination)
            }
        }
        .tabItem {
            Label("Journal", systemImage: "book")
        }
        .tag(Tab.journal)
    }

    var substancesTab: some View {
        NavigationStack(path: $navigator.substancesTabPath) {
            SearchScreen(
                isSearchFocused: _isSearchFocused,
                searchText: $navigator.substanceSearchText,
                selectedCategories: $navigator.selectedCategories,
                clearCategories: navigator.clearCategories)
            .onAppear { self.isSearchFocused = navigator.isSubstanceSearchFocused}
            .onChange(of: isSearchFocused) { navigator.isSubstanceSearchFocused = $0 }
            .onChange(of: navigator.isSubstanceSearchFocused) { isSearchFocused = $0 }
            .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                getScreen(from: destination)
            }
        }
        .tabItem {
            Label("Substances", systemImage: "pills")
        }
        .tag(Tab.substances)
    }
    
    var saferTab: some View {
        NavigationStack(path: $navigator.saferTabPath) {
            SaferScreen()
                .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                    getScreen(from: destination)
                }
        }
        .tabItem {
            Label("Safer", systemImage: "cross.case")
        }
        .tag(Tab.safer)
    }

    var settingsTab: some View {
        NavigationStack(path: $navigator.settingsTabPath) {
            SettingsScreen()
                .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                    getScreen(from: destination)
                }
        }
        .tabItem {
            Label("Settings", systemImage: "gearshape")
        }
        .tag(Tab.settings)
    }

}
