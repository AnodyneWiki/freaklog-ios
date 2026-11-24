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
}
