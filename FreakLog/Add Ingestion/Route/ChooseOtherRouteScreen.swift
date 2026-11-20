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
            RouteGrid(routes: arguments.otherRoutes) { route in
                SubstanceAndRoute(substance: arguments.substance, administrationRoute: route)
            }
        }
        .padding(.horizontal)
        .navigationBarTitle("Other Routes")
    }
}

#Preview {
    ChooseOtherRouteScreen(
        arguments: .init(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!,
                         otherRoutes: [.inhaled, .intravenous, .intramuscular, .smoked]),
        dismiss: {}
    )
}
