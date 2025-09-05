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
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .brief
        return formatter.string(from: dateComponents) ?? ""
    }

    private static func formattedWithAtLeastDays(_ dateComponents: DateComponents) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .brief
        return formatter.string(from: dateComponents) ?? ""
    }
}
