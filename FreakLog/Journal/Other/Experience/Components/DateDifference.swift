import Foundation

enum DateDifference {

    static func maxTwoUnitsBetween(_ startDate: Date, and endDate: Date) -> String {
        let components = between(startDate, and: endDate)
        return formattedWithMax2Units(components)
    }

    static func formattedWithAtLeastDaysBetween(_ startDate: Date, and endDate: Date) -> String {
        let components = between(startDate, and: endDate)
        return formattedWithAtLeastDays(components)
    }

    static func between(_ startDate: Date, and endDate: Date) -> DateComponents {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let dateDifference = calendar.dateComponents(components, from: startDate, to: endDate)
        return dateDifference
    }

    static func formattedWithMax2Units(_ dateComponents: DateComponents) -> String {
        max2UnitsFormatter.string(from: dateComponents) ?? ""
    }

    private static func formattedWithAtLeastDays(_ dateComponents: DateComponents) -> String {
        atLeastDaysFormatter.string(from: dateComponents) ?? ""
    }

    // Built once, since these format every row's time on each render
    private static let max2UnitsFormatter = formatter(units: [.year, .month, .day, .hour, .minute])
    private static let atLeastDaysFormatter = formatter(units: [.year, .month, .day])

    private static func formatter(units: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .brief
        return formatter
    }
}
