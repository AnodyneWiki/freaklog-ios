import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NowView()
                .tabItem { Label("Now", systemImage: "clock") }
            RecentExperiencesView()
                .tabItem { Label("Recent", systemImage: "list.bullet") }
            QuickAddView()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            WatchSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
