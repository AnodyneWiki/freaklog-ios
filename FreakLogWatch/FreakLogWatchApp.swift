import SwiftUI

// MARK: - FreakLogWatchApp

@main
struct FreakLogWatchApp: App {
  init() {
    WatchSession.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      SuggestionsScreen()
        .environmentObject(session)
        .environmentObject(model)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        session.refresh()
      }
    }
    .backgroundTask(.watchConnectivity) {
      await session.handleBackgroundDelivery()
    }
  }

  @StateObject private var session = WatchSession.shared
  @StateObject private var model = QuickLogModel(session: WatchSession.shared)
  @Environment(\.scenePhase) private var scenePhase

}

extension WatchSuggestion {
  var swiftUIColor: Color {
    Color(red: color.red, green: color.green, blue: color.blue)
  }

  var routeName: String {
    route.localizedCapitalized
  }

  // "Ketamine" or, for a custom unit, "Ketamine, Line"
  var title: String {
    if let customUnit {
      return "\(displayName), \(customUnit.name)"
    }
    return displayName
  }
}
