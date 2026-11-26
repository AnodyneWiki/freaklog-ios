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
            if appDelegate.isJournalReady {
                AuthenticatorWrapper(authenticator: authenticator) {
                    ContentView()
                        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
                        .environmentObject(toastViewModel)
                        .environmentObject(authenticator)
                        .environmentObject(locationManager)
                        .environmentObject(LeaderboardServerStore.shared)
                        .accentColor(Color.blue)
                        .task(id: scenePhase) {
                            if scenePhase == .active { await JournalAutomaticBackups.shared.save() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: IngestionDeletion.failureNotification)) { notification in
                            if let message = notification.object as? String {
                                toastViewModel.showErrorToast(message: message)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: WebhookManager.failureNotification)) { notification in
                            if let message = notification.object as? String {
                                toastViewModel.showErrorToast(message: message)
                            }
                        }
                        .toast(isPresenting: $toastViewModel.isShowingToast, duration: 1) {
                            AlertToast(
                                displayMode: .alert,
                                type: toastViewModel.isSuccessToast ? .complete(.green) : .error(.red),
                                title: toastViewModel.toastMessage)
                        }
                }
            } else {
                VStack(spacing: 16) {
                    Text("Couldn't open the journal")
                    Button("Retry", action: appDelegate.prepareJournal)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            authenticator.onChange(of: phase)
        }
    }
}
