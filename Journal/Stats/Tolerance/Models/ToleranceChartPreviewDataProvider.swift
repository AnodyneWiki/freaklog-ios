import Foundation

enum ToleranceChartPreviewDataProvider {
    static let mock1: [ToleranceWindow] = [
        ToleranceWindow(substanceName: "MDMA",
                        start: getDate(year: 2023, month: 2, day: 1)!,
                        end: getDate(year: 2023, month: 4, day: 1)!,
                        toleranceType: .full,
                        substanceColor: .pink),
        ToleranceWindow(substanceName: "MDMA",
                        start: getDate(year: 2023, month: 4, day: 1)!,
                        end: getDate(year: 2023, month: 5, day: 1)!,
                        toleranceType: .half,
                        substanceColor: .pink),
        ToleranceWindow(substanceName: "Ketamine",
                        start: getDate(year: 2023, month: 2, day: 10)!,
                        end: getDate(year: 2023, month: 2, day: 20)!,
                        toleranceType: .full,
                        substanceColor: .blue),
        ToleranceWindow(substanceName: "Ketamine",
                        start: getDate(year: 2023, month: 2, day: 20)!,
                        end: getDate(year: 2023, month: 2, day: 30)!,
                        toleranceType: .half,
                        substanceColor: .blue),
    ]
}
