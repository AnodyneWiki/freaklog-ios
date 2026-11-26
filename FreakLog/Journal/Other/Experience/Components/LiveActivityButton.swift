import ActivityKit
import SwiftUI

@available(iOS 16.2, *)
struct LiveActivityButton: View {
    let experience: Experience
    let startLiveActivity: () -> Void
    @ObservedObject var activityManager = ActivityManager.shared
    @AppStorage(PersistenceController.hasToUnlockAppKey) private var requiresUnlock = false
    @State private var areActivitiesEnabled = false

    var body: some View {
        Group {
            if requiresUnlock {
                Label("Live Activities Are Hidden with App Lock", systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if !ProcessInfo.processInfo.isiOSAppOnMac && areActivitiesEnabled {
                // An activity of another experience can be switched over to this one
                if activityManager.isShowing(experience) {
                    Button {
                        Task { await activityManager.stop() }
                    } label: {
                        Label("Stop Live Activity", systemImage: "stop")
                    }
                } else {
                    Button {
                        startLiveActivity()
                    } label: {
                        Label("Start Live Activity", systemImage: "play")
                    }
                }
            } else if UIDevice.current.userInterfaceIdiom == .phone {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button {
                        Task {
                            await UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Enable Live Activities", systemImage: "gearshape")
                    }
                }
            }
        }
        .task {
            guard !ProcessInfo.processInfo.isiOSAppOnMac else { return }
            let authorizationInfo = ActivityManager.shared.authorizationInfo
            self.areActivitiesEnabled = authorizationInfo.areActivitiesEnabled
            for await isEnabled in authorizationInfo.activityEnablementUpdates {
                self.areActivitiesEnabled = isEnabled
            }
        }
    }
}

@available(iOS 16.2, *)
#Preview {
    List {
        LiveActivityButton(experience: Experience(context: PersistenceController.preview.viewContext), startLiveActivity: {})
    }
}
