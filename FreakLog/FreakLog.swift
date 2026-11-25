import SwiftUI
import AlertToast

@main
struct FreakLog: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var toastViewModel = ToastViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authenticator = Authenticator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Reads AnodyneWiki's cached data before the first timeline or dose display asks for it
        Task.detached(priority: .utility) {
            AnodyneCacheFiles.discardLegacyCache()
            AnodyneFallbackStore.shared.preload()
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthenticatorWrapper(authenticator: authenticator) {
                LaunchAnimationWrapper {
                    ContentView()
                        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
                        .environmentObject(toastViewModel)
                        .environmentObject(authenticator)
                        .environmentObject(locationManager)
                        .environmentObject(LeaderboardServerStore.shared)
                        .accentColor(Color.blue)
                        .toast(isPresenting: $toastViewModel.isShowingToast, duration: 1) {
                            AlertToast(
                                displayMode: .alert,
                                type: toastViewModel.isSuccessToast ? .complete(.green) : .error(.red),
                                title: toastViewModel.toastMessage)
                        }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            authenticator.onChange(of: phase)
        }
    }
}
