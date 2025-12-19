import Foundation

extension ShulginRating: Comparable {
    public static func < (lhs: ShulginRating, rhs: ShulginRating) -> Bool {
        lhs.timeUnwrapped < rhs.timeUnwrapped
    }

    var timeUnwrapped: Date {
        time ?? Date()
    }

    var creationDateUnwrapped: Date {
        creationDate ?? Date()
    }

    var optionUnwrapped: ShulginRatingOption {
        guard let option else { return .fourPlus }
        if let result = ShulginRatingOption(rawValue: option) {
            return result
        } else {
            return .fourPlus
        }
    }
}
