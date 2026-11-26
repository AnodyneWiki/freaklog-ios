import AlertToast
import SwiftUI
import StoreKit
import CoreData

struct ContentView: View {
    @AppStorage(PersistenceController.needsToSeeWelcomeKey) var needsToSeeWelcome: Bool = true
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen2: Bool = false

    var body: some View {
        ContentScreen(isEyeOpen: isEyeOpen2)
            .sheet(isPresented: $needsToSeeWelcome) {
                WelcomeScreen(isShowingWelcome: $needsToSeeWelcome)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
            }
    }
}

struct ContentScreen: View {
    let isEyeOpen: Bool

    @ObservedObject var navigator = Navigator.shared
    @ObservedObject var tabManager = TabManager.shared
    @State private var searchFavoritesOnly = false
    @EnvironmentObject var authenticator: Authenticator

    var body: some View {
        Group {
            TabView(selection: navigator.binding) {
                ForEach(filteredTabs) { tab in
                    view(for: tab)
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
            maybeRequestAppRating()
        }) {
            AuthenticatorWrapper(authenticator: authenticator) {
                ChooseSubstanceScreen()
            }
            .environment(\.addIngestionStartTime, navigator.addIngestionStartTime)
            .environment(\.addIngestionEndTime, navigator.addIngestionEndTime)
        }
    }

    var filteredTabs: [Tab] {
        tabManager.enabledTabs.filter { isEyeOpen || !$0.requiresOpenEye }
    }

    func view(for tab: Tab) -> some View {
        NavigationStack(path: $navigator[dynamicMember: Navigator.pathKeyPath(for: tab)]) {
            rootScreen(for: tab)
                .navigationDestination(for: GlobalNavigationDestination.self) { destination in
                    getScreen(from: destination)
                }
        }
        .tabItem {
            Label(tab.title, systemImage: tab.icon)
        }
        .tag(tab)
    }

    @ViewBuilder
    private func rootScreen(for tab: Tab) -> some View {
        switch tab {
        case .stats:
            StatsScreen()
        case .journal:
            JournalScreen(isFavoriteFilterEnabled: $navigator.isFavoriteFilterEnabled)
        case .substances:
            SearchScreen(
                searchText: $navigator.substanceSearchText,
                scope: $navigator.substanceSearchScope,
                isSearchPresented: $navigator.isSubstanceSearchFocused,
                favoritesOnly: $searchFavoritesOnly
            )
        case .tools:
            ToolsScreen()
        case .settings:
            SettingsScreen()
        }
    }

    @AppStorage(PersistenceController.openUntilRatedCountKey) var openUntilRatedCount: Int = 0

    private func maybeRequestAppRating() {
        if #available(iOS 16.2, *) {
            if openUntilRatedCount < 10 {
                openUntilRatedCount += 1
            } else if openUntilRatedCount == 10 {
                if isEyeOpen && PersistenceController.shared.getIngestionCount() > 10 {
                    if let windowScene = UIApplication.shared.currentWindow?.windowScene {
                        SKStoreReviewController.requestReview(in: windowScene)
                    }
                    openUntilRatedCount += 1
                }
            }
        }
    }

}
