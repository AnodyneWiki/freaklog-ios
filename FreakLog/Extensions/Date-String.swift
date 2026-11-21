import Foundation

extension Date {
    var asDateString: String {
        Self.dateFormatter.string(from: self)
    }

    private static let dateFormatter = formatter("d MMM y")

    private static func formatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        return formatter
    }
}
