import SwiftUI

struct SaferRoutesScreen: View {
    var body: some View {
        List {
            SaferRoutesSectionContent()
        }
        .navigationTitle("Safer Routes")
    }
}

struct SaferRoutesSectionContent: View {
    var body: some View {
        Group {
            Text("Don’t share snorting equipment (straws, banknotes, bullets) to avoid blood-borne diseases such as Hepatitis C that can be transmitted through blood amounts so small you can’t notice. Injection is the the most dangerous route of administration and highly advised against. If you are determined to inject, don’t share injection materials and refer to the safer injection guide.")
            NavigationLink("Administration Routes Info", value: GlobalNavigationDestination.administrationRouteInfo)
        }
    }
}


#Preview {
    NavigationStack {
        SaferRoutesScreen()
    }
}
