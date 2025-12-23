import Foundation

struct IngestionMinInfoForTimeline: Codable, Equatable {
    static func == (lhs: IngestionMinInfoForTimeline, rhs: IngestionMinInfoForTimeline) -> Bool {
        lhs.time == rhs.time
    }

    let substanceName: String
    let route: AdministrationRoute
    let onsetDelayInHours: Double
    let time: Date
    let endTime: Date?
    let dose: Double?
    let color: SubstanceColor
}

private func getIngestionMinInfoForTimeline(ingestions: [Ingestion]) -> [IngestionMinInfoForTimeline] {
    ingestions.map { ingestion in
        IngestionMinInfoForTimeline(
            substanceName: ingestion.substanceNameUnwrapped,
            route: ingestion.administrationRouteUnwrapped,
            onsetDelayInHours: 0,
            time: ingestion.timeUnwrapped,
            endTime: ingestion.endTime,
            dose: ingestion.pureSubstanceDose,
            color: ingestion.substanceColor
        )
    }
}

// return value is ready to be sent to live activity
func getSubstanceIngestionGroups(ingestions: [Ingestion]) -> [SubstanceIngestionGroup] {
    let ingestionsMinInfoForTimeline = getIngestionMinInfoForTimeline(ingestions: ingestions)
    let substanceDict = Dictionary(grouping: ingestionsMinInfoForTimeline) { minInfo in
        minInfo.substanceName
    }
    let substanceIngestionGroups: [SubstanceIngestionGroup] = substanceDict.compactMap { (substanceName: String, ingestionMinInfoForLines: [IngestionMinInfoForTimeline]) in
        guard let color = ingestionMinInfoForLines.first?.color else { return nil }
        let routeDict = Dictionary(grouping: ingestionMinInfoForLines) { value in
            value.route
        }
        let routeMinInfos = routeDict.map { (route: AdministrationRoute, values: [IngestionMinInfoForTimeline]) in
            let ingestions = values.map { ingestionMinInfo in
                IngestionMinInfo(
                    dose: ingestionMinInfo.dose,
                    time: ingestionMinInfo.time,
                    endTime: ingestionMinInfo.endTime,
                    onsetDelayInHours: ingestionMinInfo.onsetDelayInHours
                )
            }
            return RouteMinInfo(
                route: route,
                ingestions: ingestions
            )
        }
        return SubstanceIngestionGroup(
            substanceName: substanceName,
            color: color,
            routeMinInfos: routeMinInfos
        )
    }
    return substanceIngestionGroups
}
