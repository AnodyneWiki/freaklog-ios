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
            }
    }
}

struct ContentScreen: View {
    let isEyeOpen: Bool

    @ObservedObject var navigator = Navigator.shared
    @FocusState var isSearchFocused: Bool
    @EnvironmentObject var authenticator: Authenticator

    var body: some View {
        Group {
            if isEyeOpen {
                TabView(selection: navigator.binding) {
                    statsTab

                    journalTab

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

                    NavigationStack(path: $navigator.rewindTabPath) {
                        RewindScreen()
                            .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                                getScreen(from: destination)
                            }
                    }
                    .tabItem {
                        Label("Rewind", systemImage: "calendar.badge.clock")
                    }
                    .tag(Tab.rewind)

                    settingsTab
                }
                .onOpenURL { url in
                    if url.absoluteString == openLatestExperience {
                        navigator.openLatestActiveExperience()
                    }
                }
            } else {
                TabView(selection: navigator.binding) {
                    statsTab
                    journalTab
                    settingsTab
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
