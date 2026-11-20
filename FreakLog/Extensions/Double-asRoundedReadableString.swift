import Foundation

extension Double {
    var asRoundedReadableString: String {
        let formatter = self < 1 ? Self.twoSignificantDigitsFormatter : Self.threeSignificantDigitsFormatter
        return formatter.string(from: self as NSNumber) ?? String(format: "%.1f", self)
    }

    private static let twoSignificantDigitsFormatter = significantDigitsFormatter(2)
    private static let threeSignificantDigitsFormatter = significantDigitsFormatter(3)

    private static func significantDigitsFormatter(_ digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = digits
        return formatter
    }
}
