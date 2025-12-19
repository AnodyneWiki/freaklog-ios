import Foundation

struct FinishIngestionScreenArguments: Hashable {
    let substanceName: String
    let administrationRoute: AdministrationRoute
    let dose: Double?
    let units: String?
    let isEstimate: Bool
    let estimatedDoseStandardDeviation: Double?
    var customUnit: CustomUnit?
}
