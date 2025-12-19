import SwiftUI

struct ToleranceWindow: Identifiable {
    let id = UUID()
    let substanceName: String
    let start: Date
    let end: Date
    let toleranceType: ToleranceType
    let barColor: Color

    init(substanceName: String, start: Date, end: Date, toleranceType: ToleranceType, substanceColor: Color) {
        self.substanceName = substanceName
        self.start = start
        self.end = end
        self.toleranceType = toleranceType
        switch toleranceType {
        case .full:
            barColor = substanceColor
        case .half:
            barColor = substanceColor.opacity(0.5)
        }
    }

    func contains(date: Date) -> Bool {
        start <= date && end >= date
    }
}
