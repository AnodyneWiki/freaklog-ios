import Foundation

struct SubstanceGroupWithRepoInfo {
    let substanceName: String
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
        let substance = SubstanceRepo.shared.getSubstance(name: substanceIngestionGroup.substanceName)
        let routeGroups = substanceIngestionGroup.routeMinInfos.map { routeMinInfo in
            let roaDuration = substance?.getDuration(for: routeMinInfo.route)
            let roaDose = substance?.getDose(for: routeMinInfo.route)
            let allKnownDoses = routeMinInfo.ingestions.compactMap({ ingestion in
                ingestion.dose
            })
            let averageDose = allKnownDoses.reduce(0, +) / max(1.0, Double(allKnownDoses.count))
            let ingestions = routeMinInfo.ingestions.map { ingestion in
                var horizontalWeight = 0.5
                if let dose = ingestion.dose, let roaDose {
                    let doseType = roaDose.getRangeType(for: dose, with: roaDose.units)
                    switch doseType {
                    case .thresh:
                        horizontalWeight = 0
                    case .light:
                        horizontalWeight = 0.25
                    case .common:
                        horizontalWeight = 0.5
                    case .strong:
                        horizontalWeight = 0.75
                    case .heavy:
                        horizontalWeight = 1
                    case .none:
                        horizontalWeight = 0.5
                    }
                }
                var commonDose = averageDose
                if let commonMin = roaDose?.commonMin, let commonMax = roaDose?.strongMin {
                    commonDose = (commonMin + commonMax)/2
                }
                var strengthRelativeToCommonDose = 1.0
                if let dose = ingestion.dose {
                    strengthRelativeToCommonDose = dose / commonDose
                }
                return IngestionWithRepoInfo(
                    onsetDelayInHours: ingestion.onsetDelayInHours,
                    time: ingestion.time,
                    endTime: ingestion.endTime,
                    horizontalWeight: horizontalWeight,
                    strengthRelativeToCommonDose: strengthRelativeToCommonDose
                )
            }
            return RouteGroupWithRepoInfo(
                roaDuration: roaDuration,
                ingestions: ingestions
            )
        }
        return SubstanceGroupWithRepoInfo(
            substanceName: substanceIngestionGroup.substanceName,
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

struct RouteMinInfo: Equatable, Codable {
    let route: AdministrationRoute
    let ingestions: [IngestionMinInfo]
}

struct IngestionMinInfo: Equatable, Codable {
    let dose: Double?
    let time: Date
    let endTime: Date?
    let onsetDelayInHours: Double
}
