import Foundation

extension Date {
    var asDateString: String {
        Self.dateFormatter.string(from: self)
    }

    var asDateAndTime: String {
        Self.dateAndTimeFormatter.string(from: self)
    }

    var asYear: String {
        Self.yearFormatter.string(from: self)
    }

    var asYearAndMonth: String {
        Self.yearAndMonthFormatter.string(from: self)
    }

    private static let dateFormatter = formatter("d MMM y")
    private static let dateAndTimeFormatter = formatter("d MMM y HH:mm")
    private static let yearFormatter = formatter("yyyy")
    private static let yearAndMonthFormatter = formatter("yyyy-MM")

    private static func formatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        return formatter
    }
}
