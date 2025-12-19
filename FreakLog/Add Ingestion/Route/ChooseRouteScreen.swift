import SwiftUI

struct ChooseRouteScreen: View {
    let substance: Substance
    let dismiss: () -> Void

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
                let documentedRoutes = substance.administrationRoutesUnwrapped
                let otherRoutes = AdministrationRoute.allCases.filter { route in
                    !documentedRoutes.contains(route)
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
            NavigationLink(value: AddIngestionDestination.saferRoutes) {
                Label("Safer Routes", systemImage: "info.circle")
            }
            .padding(.vertical)
        }
        .padding(.horizontal)
        .navigationBarTitle("\(substance.name) Routes")
    }

    @ViewBuilder
    private func getGroupOfRoutes(routes: [AdministrationRoute]) -> some View {
        let numOfRoutes = routes.count
        if numOfRoutes < 6 {
            ForEach(routes, id: \.self) { route in
                getRouteBoxWithNavigation(route: route)
            }
        } else {
            let numRows = Int(ceil(Double(routes.count) / 2.0))
            ForEach(0 ..< numRows, id: \.self) { index in
                HStack {
                    let route1 = routes[index * 2]
                    getRouteBoxWithNavigation(route: route1)
                    let secondIndex = index * 2 + 1
                    if secondIndex < routes.count {
                        let route2 = routes[secondIndex]
                        getRouteBoxWithNavigation(route: route2)
                    }
                }
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
            substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!,
            dismiss: {}
        )
    }
}
