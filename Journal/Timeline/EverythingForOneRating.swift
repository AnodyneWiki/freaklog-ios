import Foundation

struct EverythingForOneRating: Codable, Equatable {
    static func == (lhs: EverythingForOneRating, rhs: EverythingForOneRating) -> Bool {
        lhs.time == rhs.time
    }

    let time: Date
    let option: ShulginRatingOption
}
