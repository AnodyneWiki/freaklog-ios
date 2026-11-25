import SwiftUI

struct ChooseRouteScreen: View {
    let substance: AddIngestionSubstance
    var shortcutRoute: AdministrationRoute? = nil
    let dismiss: () -> Void
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    var screen: some View {
        let documentedRoutes = substance.documentedRoutes.filter { $0 != shortcutRoute }
        let otherRoutes = AdministrationRoute.allCases.filter { route in
            route != shortcutRoute && !documentedRoutes.contains(route)
        }
        return List {
            if let shortcutRoute {
                Section("From Shortcut") {
                    routeLink(shortcutRoute)
                }
            }
            Section {
                ForEach(documentedRoutes.isEmpty ? otherRoutes : documentedRoutes, id: \.self) { route in
                    routeLink(route)
                }
                if !documentedRoutes.isEmpty, !otherRoutes.isEmpty {
                    NavigationLink(value: ChooseOtherRouteScreenArguments(substance: substance, otherRoutes: otherRoutes)) {
                        Text("Other Routes")
                    }
                }
            } header: {
                Text(substance.displayName)
            }
            if isEyeOpen {
                Section {
                    NavigationLink(value: AddIngestionDestination.saferRoutes) {
                        Label("Safer Routes", systemImage: "info.circle")
                    }
                }
            }
        }
        .navigationTitle("Choose Route")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routeLink(_ route: AdministrationRoute) -> some View {
        NavigationLink(value: SubstanceAndRoute(substance: substance, administrationRoute: route)) {
            RouteRow(route: route)
        }
    }
}

#Preview {
    NavigationStack {
        ChooseRouteScreen(
            substance: .psychonautWiki(SubstanceRepo.shared.getSubstance(name: "MDMA")!),
            dismiss: {}
        )
    }
}
