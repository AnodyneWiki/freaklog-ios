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
        VStack(alignment: .center) {
            VStack(alignment: .leading) {
                if let shortcutRoute {
                    Text("From Shortcut")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    getRouteBoxWithNavigation(route: shortcutRoute)
                }
                let documentedRoutes = substance.documentedRoutes.filter { $0 != shortcutRoute }
                let otherRoutes = AdministrationRoute.allCases.filter { route in
                    route != shortcutRoute && !documentedRoutes.contains(route)
                }
                if documentedRoutes.isEmpty {
                    getGroupOfRoutes(routes: otherRoutes)
                } else {
                    getGroupOfRoutes(routes: documentedRoutes)
                    if !otherRoutes.isEmpty {
                        NavigationLink(value: ChooseOtherRouteScreenArguments(substance: substance,
                                                                              otherRoutes: otherRoutes)) {
                            GroupBox {
                                Text("Other Routes")
                                    .font(.headline)
                                    .frame(
                                        minWidth: 0,
                                        maxWidth: .infinity,
                                        minHeight: 0,
                                        maxHeight: .infinity,
                                        alignment: .center
                                    )
                            }
                        }
                    }
                }
            }
            if isEyeOpen {
                NavigationLink(value: AddIngestionDestination.saferRoutes) {
                    Label("Safer Routes", systemImage: "info.circle")
                }
                .padding(.vertical)
            }
        }
        .padding(.horizontal)
        .navigationBarTitle("\(substance.displayName) Routes")
    }

    @ViewBuilder
    private func getGroupOfRoutes(routes: [AdministrationRoute]) -> some View {
        let numOfRoutes = routes.count
        if numOfRoutes < 6 {
            ForEach(routes, id: \.self) { route in
                getRouteBoxWithNavigation(route: route)
            }
        } else {
            RouteGrid(routes: routes) { route in
                SubstanceAndRoute(substance: substance, administrationRoute: route)
            }
        }
    }

    private func getRouteBoxWithNavigation(route: AdministrationRoute) -> some View {
        NavigationLink(value: SubstanceAndRoute(substance: substance, administrationRoute: route)) {
            RouteBox(route: route)
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
