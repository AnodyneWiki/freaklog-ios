import SwiftUI
import AlertToast

@main
struct FreakLog: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var toastViewModel = ToastViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authenticator = Authenticator()
    @State private var pendingJournalURL: URL?
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
            Group {
                if appDelegate.isJournalReady {
                    AuthenticatorWrapper(authenticator: authenticator) {
                        ContentView()
                            .modifier(RoutineNotificationReview())
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
            .onOpenURL { url in
                guard url == continueJournalURL || url == dueTodayURL
                    || url.absoluteString == openLatestExperience else { return }
                pendingJournalURL = url
                openPendingJournalURL()
            }
            .onChange(of: authenticator.isLocked) { _ in openPendingJournalURL() }
            .onChange(of: authenticator.isStartingUp) { _ in openPendingJournalURL() }
            .onChange(of: appDelegate.isJournalReady) { ready in
                if ready { openPendingJournalURL() }
            }
            .task(id: appDelegate.isJournalReady) {
                if #available(iOS 16.2, *), appDelegate.isJournalReady {
                    await ActivityManager.shared.enforceJournalPrivacy()
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            authenticator.onChange(of: phase)
            if phase == .active, appDelegate.isJournalReady {
                Task { await RoutineSchedules.shared.refresh() }
            }
        }
    }

    @MainActor
    private func openPendingJournalURL() {
        guard let pendingJournalURL, appDelegate.isJournalReady,
              !authenticator.isStartingUp, !authenticator.isLocked else { return }
        self.pendingJournalURL = nil
        let navigator = Navigator.shared
        if pendingJournalURL == dueTodayURL {
            navigator.selectedTab = .journal
            navigator.journalTabPath = NavigationPath()
            if UserDefaults.standard.bool(forKey: PersistenceController.isEyeOpenKey2) {
                navigator.journalTabPath.append(GlobalNavigationDestination.dueToday)
            }
        } else {
            navigator.openLatestActiveExperience()
        }
    }
}
