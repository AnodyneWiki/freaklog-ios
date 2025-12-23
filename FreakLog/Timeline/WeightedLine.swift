import Foundation

struct WeightedLine {
    let startTime: Date
    let endTime: Date?
    let horizontalWeight: Double
    let strengthRelativeToCommonDose: Double
    let onsetDelayInHours: Double
    let forcedMaxStrengthOfSubstance: Double?

    init(
        startTime: Date,
        endTime: Date?,
        horizontalWeight: Double,
        strengthRelativeToCommonDose: Double,
        onsetDelayInHours: Double,
        forcedMaxStrengthOfSubstance: Double? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.horizontalWeight = horizontalWeight
        self.strengthRelativeToCommonDose = strengthRelativeToCommonDose
        self.onsetDelayInHours = onsetDelayInHours
        self.forcedMaxStrengthOfSubstance = forcedMaxStrengthOfSubstance
    }
}
