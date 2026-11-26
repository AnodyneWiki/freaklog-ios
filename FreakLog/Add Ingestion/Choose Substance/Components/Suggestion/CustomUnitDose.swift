import Foundation

struct CustomUnitDose: Equatable, Identifiable {

    var id: String {
        "\(dose)\(isEstimate)\(customUnit.description)"
    }

    let dose: Double
    let isEstimate: Bool
    let estimatedStandardDeviation: Double?
    let customUnit: CustomUnit

    // https://en.m.wikipedia.org/wiki/Distribution_of_the_product_of_two_random_variables
    // E(X*Y) = E(X) * E(Y)
    var calculatedDose: Double? {
        if let dosePerUnit = customUnit.doseUnwrapped {
            return dose * dosePerUnit
        } else {
            return nil
        }
    }

    // https://www.mathsisfun.com/data/standard-deviation.html
    // https://en.m.wikipedia.org/wiki/Distribution_of_the_product_of_two_random_variables
    // Var(X*Y) = (Var(X) + E(X)^2)*(Var(Y) + E(Y)^2) - E(X)^2 * E(Y)^2
    var calculatedStandardDeviation: Double? {
        guard let dosePerUnit = customUnit.doseUnwrapped else { return nil }
        return Self.productDeviation(
            amount: dose, amountDeviation: isEstimate ? estimatedStandardDeviation : nil,
            dosePerUnit: dosePerUnit, doseDeviation: customUnit.estimatedDoseStandardDeviationUnwrapped)
    }

    static func productDeviation(amount: Double, amountDeviation: Double?, dosePerUnit: Double, doseDeviation: Double?) -> Double? {
        let amountSD = amountDeviation ?? 0
        let doseSD = doseDeviation ?? 0
        let variance = pow(amountSD * doseSD, 2) + pow(amountSD * dosePerUnit, 2) + pow(doseSD * amount, 2)
        return variance > 0.0000001 ? sqrt(variance) : nil
    }

    // 20 mg
    var calculatedDoseDescription: String? {
        calculatedDose?.doseDescription(
            units: customUnit.originalUnitUnwrapped,
            isEstimate: isEstimate || customUnit.isEstimate || calculatedStandardDeviation != nil,
            standardDeviation: calculatedStandardDeviation,
            rounded: true
        )
    }

    // 2 pills
    var doseDescription: String {
        Self.description(of: dose, isEstimate: isEstimate, standardDeviation: estimatedStandardDeviation, customUnit: customUnit)
    }

    // A number of custom units, e.g. "2 pills" or "~1 spoon"
    static func description(of dose: Double, isEstimate: Bool, standardDeviation: Double?, customUnit: CustomUnit) -> String {
        dose.doseDescription(
            units: dose.justUnit(pluralizableUnit: customUnit.pluralizableUnit),
            isEstimate: isEstimate,
            standardDeviation: standardDeviation,
            rounded: true
        )
    }

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.calculatedDoseDescription == rhs.calculatedDoseDescription && lhs.doseDescription == rhs.doseDescription
    }
}
