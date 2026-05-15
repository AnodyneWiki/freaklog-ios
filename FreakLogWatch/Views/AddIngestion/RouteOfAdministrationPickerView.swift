import SwiftUI

struct RouteOfAdministrationPickerView: View {
    let substance: SubstanceLite
    @Binding var path: NavigationPath

    var routes: [AdministrationRoute] {
        substance.fullSubstance?.roas.map { $0.name } ?? AdministrationRoute.allCases
    }

    var body: some View {
        List(routes, id: \.self) { route in
            Button {
                path.append(AddRoute.dose(substance, route))
            } label: {
                Text(route.rawValue.capitalized)
            }
        }
        .navigationTitle(substance.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
