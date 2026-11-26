import CoreData
import Foundation

struct RatingCodable: Codable {
    let creationDate: Date?
    let time: Date?
    let option: ShulginRatingOption

    init(
        creationDate: Date,
        time: Date?,
        option: ShulginRatingOption
    ) {
        self.creationDate = creationDate
        self.time = time
        self.option = option
    }

    enum CodingKeys: String, CodingKey {
        case creationDate
        case time
        case option
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try values.decodeMillisIfPresent(forKey: .creationDate)
        time = try values.decodeMillisIfPresent(forKey: .time)
        option = try values.decode(ShulginRatingOption.self, forKey: .option)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeMillis(creationDate, forKey: .creationDate)
        try container.encodeMillis(time, forKey: .time)
        try container.encode(option, forKey: .option)
    }
}

extension RatingCodable {
    init(_ rating: ShulginRating) {
        self.init(creationDate: rating.creationDateUnwrapped, time: rating.time, option: rating.optionUnwrapped)
    }

    func insert(into context: NSManagedObjectContext, fallbackDate: Date) -> ShulginRating {
        let rating = ShulginRating(context: context)
        rating.creationDate = creationDate ?? time ?? fallbackDate
        rating.time = time
        rating.option = option.rawValue
        return rating
    }
}
