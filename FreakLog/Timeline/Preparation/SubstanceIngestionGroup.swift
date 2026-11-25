import Foundation

// return value is ready to be sent to live activity
func getSubstanceIngestionGroups(ingestions: [Ingestion]) -> [SubstanceIngestionGroup] {
    let visible = ingestions.filter { !$0.isHiddenFromTimeline && !$0.isUnconfirmed }
    return Dictionary(grouping: visible, by: \.substanceNameUnwrapped).compactMap { substanceName, ingestionsForSubstance in
        guard let color = ingestionsForSubstance.first?.substanceColor else { return nil }
        let routeMinInfos = Dictionary(grouping: ingestionsForSubstance, by: \.administrationRouteUnwrapped).map { route, ingestionsForRoute in
            RouteMinInfo.resolved(
                substanceName: substanceName,
                route: route,
                ingestions: ingestionsForRoute.map { ingestion in
                    IngestionMinInfo(
                        dose: ingestion.pureSubstanceDose,
                        time: ingestion.timeUnwrapped,
                        endTime: ingestion.endTime,
                        onsetDelayInHours: 0,
                        doseUnits: ingestion.pureUnits
                    )
                }
            )
        }
        return SubstanceIngestionGroup(substanceName: substanceName, color: color, routeMinInfos: routeMinInfos)
    }
}

extension RouteMinInfo {
    // Fills in duration and dose info from PW data and custom overrides.
    static func resolved(substanceName: String, route: AdministrationRoute, ingestions: [IngestionMinInfo]) -> RouteMinInfo {
        let resolved = PersistenceController.shared.resolvedRoa(for: substanceName, route: route)
        return RouteMinInfo(
            route: route,
            ingestions: ingestions.map { $0.withHorizontalWeight(for: resolved.dose) },
            roaDuration: resolved.duration,
            commonDose: resolved.dose?.averageCommonDose,
            commonDoseUnits: resolved.dose?.units
        )
    }
}

private extension IngestionMinInfo {
    func withHorizontalWeight(for roaDose: RoaDose?) -> IngestionMinInfo {
        guard let dose, dose.isFinite, dose > 0, let doseUnits, let roaDose else { return self }
        var copy = self
        switch roaDose.getRangeType(for: dose, with: doseUnits) {
        case .thresh: copy.horizontalWeight = 0
        case .light: copy.horizontalWeight = 0.25
        case .common, .none: copy.horizontalWeight = 0.5
        case .strong: copy.horizontalWeight = 0.75
        case .heavy: copy.horizontalWeight = 1
        }
        return copy
    }
}
