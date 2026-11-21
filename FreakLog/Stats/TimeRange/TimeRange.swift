import Foundation

enum TimeRange {
    case last30Days
    case last12Months
    case years

    // The calendar period each bar of a chart covers
    var period: Calendar.Component {
        switch self {
        case .last30Days: .day
        case .last12Months: .month
        case .years: .year
        }
    }

    var periodComponents: Set<Calendar.Component> {
        switch self {
        case .last30Days: [.year, .month, .day]
        case .last12Months: [.year, .month]
        case .years: [.year]
        }
    }
}
