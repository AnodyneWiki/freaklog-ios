import Foundation

protocol SuggestionProtocol: Identifiable {
    var id: String { get }
    var sortDate: Date { get }

    func isInResult(searchText: String, substanceNames: [String]) -> Bool
}

struct PureSubstanceSuggestions: SuggestionProtocol {
    func isInResult(searchText: String, substanceNames: [String]) -> Bool {
        substanceNames.contains(substance.name)
    }

    let id: String
    let route: AdministrationRoute
    let substance: Substance
    let substanceColor: SubstanceColor
    let dosesAndUnit: [RegularDoseAndUnit]
    let sortDate: Date

    init(route: AdministrationRoute, substance: Substance, substanceColor: SubstanceColor, dosesAndUnit: [RegularDoseAndUnit], sortDate: Date) {
        self.route = route
        self.substance = substance
        self.substanceColor = substanceColor
        self.dosesAndUnit = dosesAndUnit
        self.sortDate = sortDate
        self.id = substance.name + route.rawValue
    }
}

struct CustomUnitSuggestions: SuggestionProtocol {
    func isInResult(searchText: String, substanceNames: [String]) -> Bool {
        if searchText.isEmpty {
            return true
        }
        return substanceNames.contains(customUnit.substanceNameUnwrapped) || customUnit.nameUnwrapped.lowercased().contains(searchText.lowercased()) || customUnit.unitUnwrapped.lowercased().contains(searchText.lowercased()) ||
        customUnit.noteUnwrapped.lowercased().contains(searchText.lowercased())
    }

    let id: String
    let customUnit: CustomUnit
    let doses: [CustomUnitDoseSuggestion]
    let substanceColor: SubstanceColor
    let sortDate: Date

    init(customUnit: CustomUnit, doses: [CustomUnitDoseSuggestion], substanceColor: SubstanceColor, sortDate: Date) {
        self.customUnit = customUnit
        self.doses = doses
        self.substanceColor = substanceColor
        self.sortDate = sortDate
        self.id = customUnit.nameUnwrapped + customUnit.substanceNameUnwrapped
    }
}

struct CustomSubstanceSuggestions: SuggestionProtocol {
    func isInResult(searchText: String, substanceNames: [String]) -> Bool {
        if searchText.isEmpty {
            return true
        }
        return customSubstanceName.lowercased().contains(searchText.lowercased())
    }
    
    let id: String
    let administrationRoute: AdministrationRoute
    let customSubstanceName: String
    let dosesAndUnit: [RegularDoseAndUnit]
    let substanceColor: SubstanceColor
    let sortDate: Date

    init(administrationRoute: AdministrationRoute, customSubstanceName: String, dosesAndUnit: [RegularDoseAndUnit], substanceColor: SubstanceColor, sortDate: Date) {
        self.administrationRoute = administrationRoute
        self.customSubstanceName = customSubstanceName
        self.dosesAndUnit = dosesAndUnit
        self.substanceColor = substanceColor
        self.sortDate = sortDate
        self.id = administrationRoute.rawValue + customSubstanceName
    }
}

// The amounts recently taken of a formulation, which its ingestions are suggested as together
struct FormulationSuggestions: SuggestionProtocol {
    func isInResult(searchText: String, substanceNames: [String]) -> Bool {
        formulation.matches(searchText: searchText)
    }

    var id: String {
        formulation.objectID.uriRepresentation().absoluteString
    }

    let formulation: Formulation
    // Most recent first
    let amounts: [Double]
    let sortDate: Date
}

struct CustomUnitDoseSuggestion: Identifiable, Equatable {
    let id = UUID()
    let dose: Double?
    let isEstimate: Bool
    let estimatedStandardDeviation: Double?

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.dose == rhs.dose && lhs.isEstimate == rhs.isEstimate && lhs.estimatedStandardDeviation == rhs.estimatedStandardDeviation
    }
}
