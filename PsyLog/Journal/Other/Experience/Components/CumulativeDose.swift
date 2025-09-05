import Foundation

struct CumulativeDose: Identifiable {
    var id: String {
        substanceName
    }

    let substanceName: String
    let substanceColor: SubstanceColor
    let cumulativeRoutes: [CumulativeRouteAndDose]

    init(ingestionsForSubstance: [Ingestion], substanceName: String, substanceColor: SubstanceColor) {
        self.substanceName = substanceName
        self.substanceColor = substanceColor
        let substance = ingestionsForSubstance.first?.substance
        let ingestionsByRoute = Dictionary(grouping: ingestionsForSubstance, by: { $0.administrationRouteUnwrapped })
        cumulativeRoutes = ingestionsByRoute.map { (route: AdministrationRoute, ingestions: [Ingestion]) in
            let roaDose = substance?.getDose(for: route)
            return CumulativeRouteAndDose(route: route, roaDose: roaDose, ingestionForRoute: ingestions)
        }
    }
}

struct CumulativeRouteAndDose: Identifiable {
    var id: AdministrationRoute {
        route
    }

    let route: AdministrationRoute
    let numDots: Int?
    let isEstimate: Bool
    let estimatedDoseStandardDeviation: Double?
    let dose: Double?
    let units: String

    init(route: AdministrationRoute, roaDose: RoaDose?, ingestionForRoute: [Ingestion]) {
        self.route = route
        let units = ingestionForRoute.first?.pureUnits ?? ""
        self.units = units
        var totalDose = 0.0
        var totalStandardDeviation = 0.0
        var isOneDoseUnknown = false
        var isOneDoseAnEstimate = false
        for ingestion in ingestionForRoute {
            if ingestion.isEstimate || ingestion.customUnit?.isEstimate == true {
                isOneDoseAnEstimate = true
            }
            let ingestionPureUnits = ingestion.pureUnits
            if let doseUnwrap = ingestion.pureSubstanceDose, ingestionPureUnits == units {
                totalDose += doseUnwrap
                if let deviation = ingestion.pureSubstanceEstimatedDoseStandardDeviation {
                    totalStandardDeviation += deviation
                }
            } else {
                isOneDoseUnknown = true
                break
            }
        }
        if isOneDoseUnknown {
            dose = nil
            numDots = nil
        } else {
            dose = totalDose
            numDots = roaDose?.getNumDots(ingestionDose: totalDose, ingestionUnits: units)
        }
        isEstimate = isOneDoseAnEstimate
        estimatedDoseStandardDeviation = totalStandardDeviation
    }

    init(route: AdministrationRoute, numDots: Int?, isEstimate: Bool, estimatedDoseStandardDeviation: Double?, dose: Double?, units: String) {
        self.route = route
        self.numDots = numDots
        self.isEstimate = isEstimate
        self.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation
        self.dose = dose
        self.units = units
    }
}
