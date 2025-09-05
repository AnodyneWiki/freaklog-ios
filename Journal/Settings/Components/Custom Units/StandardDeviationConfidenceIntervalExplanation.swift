import SwiftUI

// https://online.stat.psu.edu/stat200/lesson/2/2.2/2.2.7#:~:text=The%2095%25%20Rule%20states%20that,mean%20on%20a%20normal%20distribution
enum StandardDeviationConfidenceIntervals {
    static func getOneStandardDeviationText(mean: Double, standardDeviation: Double, unit: String) -> String {
        let lowerRange = mean - standardDeviation
        let higherRange = mean + standardDeviation
        return "\(lowerRange.asRoundedReadableString)-\(higherRange.asRoundedReadableString) \(unit) in 68% of cases"
    }

    static func getTwoStandardDeviationText(mean: Double, standardDeviation: Double, unit: String) -> String {
        let twoStandardDeviations = 2*standardDeviation
        let lowerRange = mean - twoStandardDeviations
        let higherRange = mean + twoStandardDeviations
        return "\(lowerRange.asRoundedReadableString)-\(higherRange.asRoundedReadableString) \(unit) in 95% of cases"
    }
}

struct StandardDeviationConfidenceIntervalExplanation: View {

    let mean: Double
    let standardDeviation: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(mean.formatted())±\(standardDeviation.formatted()) \(unit) means:")
            Text(StandardDeviationConfidenceIntervals.getOneStandardDeviationText(mean: mean, standardDeviation: standardDeviation, unit: unit))
            Text(StandardDeviationConfidenceIntervals.getTwoStandardDeviationText(mean: mean, standardDeviation: standardDeviation, unit: unit))
        }.foregroundStyle(.secondary)
    }
}
