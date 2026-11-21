import Foundation

// The substance an ingestion or custom unit is added for: one from PsychonautWiki or one the user defined.
// Both go through the same route, dose and custom unit screens.
enum AddIngestionSubstance: Hashable {
    case psychonautWiki(Substance)
    case custom(name: String, units: String)

    var name: String {
        switch self {
        case .psychonautWiki(let substance): substance.name
        case .custom(let name, _): name
        }
    }

    var displayName: String {
        PersistenceController.shared.displayName(for: name)
    }

    var psychonautWikiSubstance: Substance? {
        if case .psychonautWiki(let substance) = self { substance } else { nil }
    }

    // Custom substances are logged in the units they were defined with
    var customSubstanceUnits: String? {
        if case .custom(_, let units) = self { units } else { nil }
    }

    // Routes with dose or duration data, listed before the others on the route screen
    var documentedRoutes: [AdministrationRoute] {
        switch self {
        case .psychonautWiki(let substance):
            return substance.administrationRoutesUnwrapped
        case .custom(let name, _):
            let customRoas = PersistenceController.shared.getCustomSubstance(name: name)?.customRoasSorted ?? []
            let routes = Set(customRoas.map(\.administrationRouteUnwrapped))
            return AdministrationRoute.allCases.filter(routes.contains)
        }
    }
}

struct SubstanceAndRoute: Hashable {
    let substance: AddIngestionSubstance
    let administrationRoute: AdministrationRoute
}
