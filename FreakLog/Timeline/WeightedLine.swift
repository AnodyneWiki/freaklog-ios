import Foundation

struct WeightedLine {
    let startTime: Date
    let endTime: Date?
    let horizontalWeight: Double
    let strengthRelativeToCommonDose: Double
    let onsetDelayInHours: Double
}
