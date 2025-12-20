import SwiftUI

struct TabSettingsScreen: View {
    @ObservedObject var tabManager = TabManager.shared
    
    var body: some View {
        List {
            Section(header: Text("Active Tabs"), footer: Text("These tabs appear in your navigation bar.")) {
                ForEach(tabManager.enabledTabs) { tab in
                    HStack {
                        Image(systemName: tab.icon)
                            .frame(width: 24)
                            .foregroundColor(.accentColor)
                        Text(tab.title)
                        
                        Spacer()
                        
                        if !tab.isMandatory {
                            Button {
                                withAnimation {
                                    tabManager.toggleVisibility(for: tab)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if !tabManager.disabledTabs.isEmpty {
                Section(header: Text("Disabled Tabs")) {
                    ForEach(tabManager.disabledTabs) { tab in
                        HStack {
                            Image(systemName: tab.icon)
                                .frame(width: 24)
                                .foregroundColor(.secondary)
                            Text(tab.title)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button {
                                withAnimation {
                                    tabManager.toggleVisibility(for: tab)
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Customize Tabs")
    }
}
