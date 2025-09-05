import Foundation

extension Double {
    var asRoundedReadableString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        let numSignificantDigits = self < 1 ? 2 : 3
        formatter.maximumSignificantDigits = numSignificantDigits
        return formatter.string(from: self as NSNumber) ?? String(format: "%.1f", self)
    }
}
