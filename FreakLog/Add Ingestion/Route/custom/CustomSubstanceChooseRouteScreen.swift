import SwiftUI

struct CustomSubstanceChooseRouteScreen: View {
    let arguments: CustomSubstanceChooseRouteScreenArguments
    let dismiss: () -> Void
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false

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
                RouteGrid(routes: Self.routes) { route in
                    CustomChooseDoseScreenArguments(
                        substanceName: arguments.substanceName,
                        units: arguments.units,
                        administrationRoute: route
                    )
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
        .navigationTitle("\(arguments.substanceName) Routes")
    }

    private static let routes: [AdministrationRoute] = [
        .oral, .insufflated, .smoked, .inhaled, .sublingual, .buccal,
        .rectal, .transdermal, .subcutaneous, .intravenous, .intramuscular,
    ]
}

#Preview {
    NavigationStack {
        CustomSubstanceChooseRouteScreen(arguments: .init(substanceName: "Coffee", units: "cups"), dismiss: {})
    }
}
