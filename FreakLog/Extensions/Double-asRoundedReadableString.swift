import Foundation

extension Double {
    var asRoundedReadableString: String {
        let formatter = self < 1 ? Self.twoSignificantDigitsFormatter : Self.threeSignificantDigitsFormatter
        return formatter.string(from: self as NSNumber) ?? String(format: "%.1f", self)
    }

    // "20 mg", "~20 mg" (estimate) or "20±5 mg" (estimate with standard deviation).
    // `rounded` uses asRoundedReadableString, e.g. for calculated or summed doses.
    func doseDescription(units: String, isEstimate: Bool, standardDeviation: Double?, rounded: Bool = false) -> String {
        let format: (Double) -> String = rounded ? { $0.asRoundedReadableString } : { $0.formatted() }
        let unitSuffix = units.isEmpty ? "" : " \(units)"
        if isEstimate, let standardDeviation, standardDeviation > 0 {
            return "\(format(self))±\(format(standardDeviation))\(unitSuffix)"
        }
        return (isEstimate ? "~" : "") + format(self) + unitSuffix
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
