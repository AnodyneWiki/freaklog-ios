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
                HStack {
                    getRouteBoxFor(route: .oral)
                    getRouteBoxFor(route: .insufflated)
                }
                HStack {
                    getRouteBoxFor(route: .smoked)
                    getRouteBoxFor(route: .inhaled)
                }
                HStack {
                    getRouteBoxFor(route: .sublingual)
                    getRouteBoxFor(route: .buccal)
                }
                HStack {
                    getRouteBoxFor(route: .rectal)
                    getRouteBoxFor(route: .transdermal)
                }
                HStack {
                    getRouteBoxFor(route: .subcutaneous)
                    getRouteBoxFor(route: .intravenous)
                }
                getRouteBoxFor(route: .intramuscular)
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

    private func getRouteBoxFor(route: AdministrationRoute) -> some View {
        NavigationLink(value: CustomChooseDoseScreenArguments(substanceName: arguments.substanceName,
                                                              units: arguments.units,
                                                              administrationRoute: route)) {
            GroupBox {
                VStack(alignment: .center) {
                    Text(route.rawValue.localizedCapitalized)
                        .font(.headline)
                    Text(route.clarification)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
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

#Preview {
    NavigationStack {
        CustomSubstanceChooseRouteScreen(arguments: .init(substanceName: "Coffee", units: "cups"), dismiss: {})
    }
}
