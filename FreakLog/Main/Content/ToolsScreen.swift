import SwiftUI

struct ToolsScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                tools.labelStyle(.titleOnly)
            } else {
                tools
            }
        }
        .navigationTitle("Tools")
    }

    private var tools: some View {
        List {
            Section {
                NavigationLink {
                    InventoryScreen()
                } label: {
                    Label("Inventory", systemImage: "archivebox")
                }
            }
            Section {
                NavigationLink(value: GlobalNavigationDestination.sprayCalculator) {
                    Label("Spray Calculator", systemImage: "eyedropper")
                }
            }
            Section {
                NavigationLink(value: GlobalNavigationDestination.saferUse) {
                    Label("Safer Use", systemImage: "cross.case")
                }
            }
        }
    }
}
