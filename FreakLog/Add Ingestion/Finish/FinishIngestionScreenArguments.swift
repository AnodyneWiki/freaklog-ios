import Foundation

struct FinishIngestionScreenArguments: Hashable {
    let substanceName: String
    let administrationRoute: AdministrationRoute
    let dose: Double?
    let units: String?
    let isEstimate: Bool
    let estimatedDoseStandardDeviation: Double?
    var customUnit: CustomUnit?
    // Set when logging a formulation, which then suggests the amount again instead of each substance
    var formulation: Formulation?
    var formulationAmount: Double?
    var isHiddenInTimeline = false

    var reviewAmount: String {
        guard let dose else { return String(localized: "Unknown amount") }
        return dose.doseDescription(
            units: customUnit?.unitUnwrapped ?? units ?? "",
            isEstimate: isEstimate,
            standardDeviation: estimatedDoseStandardDeviation
        )
    }
}
