import ActivityKit
import SwiftUI

@available(iOS 16.2, *)
struct LiveActivityButton: View {
    let stopLiveActivity: () -> Void
    let startLiveActivity: () -> Void
    @ObservedObject var activityManager = ActivityManager.shared
    @State private var areActivitiesEnabled = false

    var body: some View {
        Group {
            if !ProcessInfo.processInfo.isiOSAppOnMac && areActivitiesEnabled {
                if activityManager.isActivityActive {
                    Button {
                        stopLiveActivity()
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
        LiveActivityButton(stopLiveActivity: {}, startLiveActivity: {})
    }
}
