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
        List {
            Section {
                ForEach(arguments.otherRoutes, id: \.self) { route in
                    NavigationLink(value: SubstanceAndRoute(substance: arguments.substance, administrationRoute: route)) {
                        RouteRow(route: route)
                    }
                }
            } header: {
                Text(arguments.substance.displayName)
            }
        }
        .navigationTitle("Other Routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ChooseOtherRouteScreen(
        arguments: .init(substance: .psychonautWiki(SubstanceRepo.shared.getSubstance(name: "MDMA")!),
                         otherRoutes: [.inhaled, .intravenous, .intramuscular, .smoked]),
        dismiss: {}
    )
}
