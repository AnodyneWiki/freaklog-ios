import Foundation

enum TimeRange {
    case last30Days
    case last12Months
    case years

    func includes(_ date: Date, relativeTo now: Date = .now) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let start: Date?
        switch self {
        case .last30Days: start = calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case .last12Months: start = calendar.date(byAdding: .month, value: -12, to: startOfToday)
        case .years: return true
        }
        return date >= (start ?? startOfToday) && date <= now
    }

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
