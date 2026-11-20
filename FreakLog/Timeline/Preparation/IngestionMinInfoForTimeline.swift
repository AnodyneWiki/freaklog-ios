import Foundation

struct SubstanceGroupWithRepoInfo {
    let color: SubstanceColor
    let routeGroups: [RouteGroupWithRepoInfo]
}

struct RouteGroupWithRepoInfo {
    let roaDuration: RoaDuration?
    let ingestions: [IngestionWithRepoInfo]
}

struct IngestionWithRepoInfo {
    let onsetDelayInHours: Double
    let time: Date
    let endTime: Date?
    let horizontalWeight: Double
    let strengthRelativeToCommonDose: Double
}

func getSubstanceGroupWithRepoInfo(substanceIngestionGroups: [SubstanceIngestionGroup]) -> [SubstanceGroupWithRepoInfo] {
    substanceIngestionGroups.map { substanceIngestionGroup in
        let routeGroups = substanceIngestionGroup.routeMinInfos.map { routeMinInfo in
            let allKnownDoses = routeMinInfo.ingestions.compactMap { $0.dose }
            let averageDose = allKnownDoses.reduce(0, +) / max(1.0, Double(allKnownDoses.count))
            let commonDose = routeMinInfo.commonDose ?? averageDose
            let ingestions = routeMinInfo.ingestions.map { ingestion in
                IngestionWithRepoInfo(
                    onsetDelayInHours: ingestion.onsetDelayInHours,
                    time: ingestion.time,
                    endTime: ingestion.endTime,
                    horizontalWeight: ingestion.horizontalWeight,
                    strengthRelativeToCommonDose: ingestion.dose.map { $0 / commonDose } ?? 1
                )
            }
            return RouteGroupWithRepoInfo(
                roaDuration: routeMinInfo.roaDuration,
                ingestions: ingestions
            )
        }
        return SubstanceGroupWithRepoInfo(
            color: substanceIngestionGroup.color,
            routeGroups: routeGroups
        )
    }
}

struct SubstanceIngestionGroup: Equatable, Codable {
    let substanceName: String
    let color: SubstanceColor
    let routeMinInfos: [RouteMinInfo]
}

// Carries the resolved duration and dose info so the timeline (and the widget) never has to look it up.
struct RouteMinInfo: Equatable, Codable {
    let route: AdministrationRoute
    let ingestions: [IngestionMinInfo]
    var roaDuration: RoaDuration?
    // Midpoint of the common dose range, if known
    var commonDose: Double?
}

struct IngestionMinInfo: Equatable, Codable {
    let dose: Double?
    let time: Date
    let endTime: Date?
    let onsetDelayInHours: Double
    // 0 (threshold) ... 1 (heavy), 0.5 when unknown
    var horizontalWeight = 0.5
}
