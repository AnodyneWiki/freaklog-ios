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
            let doseUnits = Set(routeMinInfo.ingestions.compactMap(\.doseUnits))
            let referenceUnits = routeMinInfo.commonDoseUnits ?? (doseUnits.count == 1 ? doseUnits.first : nil)
            func comparableDose(for ingestion: IngestionMinInfo) -> Double? {
                guard (doseUnits.isEmpty || ingestion.doseUnits == referenceUnits),
                      let dose = ingestion.dose, dose.isFinite, dose > 0 else { return nil }
                return dose
            }
            let allKnownDoses = routeMinInfo.ingestions.compactMap { comparableDose(for: $0) }
            let averageDose = allKnownDoses.reduce(0, +) / max(1.0, Double(allKnownDoses.count))
            let commonDose = [routeMinInfo.commonDose, averageDose].compactMap { $0 }.first { $0.isFinite && $0 > 0 } ?? 1
            let ingestions = routeMinInfo.ingestions.map { ingestion in
                IngestionWithRepoInfo(
                    onsetDelayInHours: ingestion.onsetDelayInHours,
                    time: ingestion.time,
                    endTime: ingestion.endTime,
                    horizontalWeight: ingestion.horizontalWeight,
                    strengthRelativeToCommonDose: comparableDose(for: ingestion).map { $0 / commonDose } ?? 1
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

struct SubstanceIngestionGroup: Hashable, Codable {
    let substanceName: String
    let color: SubstanceColor
    let routeMinInfos: [RouteMinInfo]
}

// Carries the resolved duration and dose info so the timeline (and the widget) never has to look it up.
struct RouteMinInfo: Hashable, Codable {
    let route: AdministrationRoute
    let ingestions: [IngestionMinInfo]
    var roaDuration: RoaDuration?
    // Midpoint of the common dose range, if known
    var commonDose: Double?
    var commonDoseUnits: String? = nil

    var canCombine: Bool {
        guard let commonDose, commonDose.isFinite, commonDose > 0, let commonDoseUnits, !ingestions.isEmpty else { return false }
        return ingestions.allSatisfy {
            $0.doseUnits == commonDoseUnits && ($0.dose ?? 0) > 0
                && TimelineEffectEstimate(substance: "", route: self, ingestion: $0) != nil
        }
    }
}

struct IngestionMinInfo: Hashable, Codable {
    let dose: Double?
    let time: Date
    let endTime: Date?
    let onsetDelayInHours: Double
    // 0 (threshold) ... 1 (heavy), 0.5 when unknown
    var horizontalWeight = 0.5
    var doseUnits: String? = nil
}
