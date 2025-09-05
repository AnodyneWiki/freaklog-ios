import SwiftUI

struct ChooseOtherRouteScreen: View {
    let arguments: ChooseOtherRouteScreenArguments
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
        VStack(alignment: .leading) {
            let numRows = Int(ceil(Double(arguments.otherRoutes.count) / 2.0))
            ForEach(0 ..< numRows, id: \.self) { index in
                HStack {
                    let route1 = arguments.otherRoutes[index * 2]
                    getRouteBoxWithNavigation(route: route1)
                    let secondIndex = index * 2 + 1
                    if secondIndex < arguments.otherRoutes.count {
                        let route2 = arguments.otherRoutes[secondIndex]
                        getRouteBoxWithNavigation(route: route2)
                    }
                }
            }
        }
        .padding(.horizontal)
        .navigationBarTitle("Other Routes")
    }

    private func getRouteBoxWithNavigation(route: AdministrationRoute) -> some View {
        NavigationLink(value: SubstanceAndRoute(substance: arguments.substance, administrationRoute: route)) {
            RouteBox(route: route)
        }
    }
}

#Preview {
    ChooseOtherRouteScreen(
        arguments: .init(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!,
                         otherRoutes: [.inhaled, .intravenous, .intramuscular, .smoked]),
        dismiss: {}
    )
}
