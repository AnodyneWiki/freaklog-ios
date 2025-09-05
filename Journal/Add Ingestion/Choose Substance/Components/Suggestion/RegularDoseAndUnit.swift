import Foundation

struct RegularDoseAndUnit: Equatable, Identifiable {
    var id: String {
        (dose?.description ?? "") + units + isEstimate.description + (estimatedDoseStandardDeviation?.description ?? "")
    }

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.doseDescription == rhs.doseDescription
    }

    let dose: Double?
    let units: String
    let isEstimate: Bool
    let estimatedDoseStandardDeviation: Double?

    var doseDescription: String? {
        if let dose {
            if isEstimate {
                if let estimatedDoseStandardDeviation {
                    return "\(dose.formatted())±\(estimatedDoseStandardDeviation.formatted()) \(units)"
                } else {
                    return "~\(dose.formatted()) \(units)"
                }
            } else {
                return "\(dose.formatted()) \(units)"
            }
        } else {
            return nil
        }
    }
}
