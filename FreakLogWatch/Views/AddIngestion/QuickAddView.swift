import SwiftUI
import CoreData

struct QuickAddView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Recent Substances") {
                    RecentSubstancesList(path: $path)
                }
                Section("Browse") {
                    NavigationLink(value: AddRoute.substancePicker) {
                        Label("All Substances", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("Add")
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .substancePicker:
                    SubstancePickerView(path: $path)
                case .roa(let substance):
                    RouteOfAdministrationPickerView(substance: substance, path: $path)
                case .dose(let substance, let route):
                    DoseEntryView(substance: substance, route: route, path: $path)
                }
            }
        }
    }
}

enum AddRoute: Hashable {
    case substancePicker
    case roa(SubstanceLite)
    case dose(SubstanceLite, AdministrationRoute)
}

/// Minimal value-type wrapper so we can put it in NavigationPath (Substance class is reference but heavy)
struct SubstanceLite: Hashable {
    let name: String
    let color: SubstanceColor

    init(name: String, color: SubstanceColor = .purple) {
        self.name = name
        self.color = color
    }

    init(from substance: Substance) {
        self.name = substance.name
        self.color = getColor(for: substance.name)
    }

    var fullSubstance: Substance? {
        SubstanceRepo.shared.getSubstance(name: name)
    }
}
