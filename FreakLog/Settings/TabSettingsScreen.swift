import SwiftUI

struct TabSettingsScreen: View {
    @ObservedObject private var tabManager = TabManager.shared

    var body: some View {
        List {
            Section {
                ForEach(Tab.allCases.filter { !$0.isMandatory }) { tab in
                    Toggle(isOn: Binding(
                        get: { !tabManager.hiddenTabs.contains(tab) },
                        set: { tabManager.setVisibility(for: tab, isVisible: $0) }
                    )) {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                }
            } header: {
                Text("Show in Tab Bar")
            } footer: {
                Text("Journal and Settings always appear.")
            }
        }
        .navigationTitle("Customize Tabs")
    }
}
