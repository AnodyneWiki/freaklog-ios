import Foundation

struct RatingCodable: Codable {
    let creationDate: Date
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
        let creationDateMillis = try values.decode(UInt64.self, forKey: .creationDate)
        creationDate = getDateFromMillis(millis: creationDateMillis)
        if let timeMillis = try values.decodeIfPresent(UInt64.self, forKey: .time) {
            time = getDateFromMillis(millis: timeMillis)
        } else {
            time = nil
        }
        option = try values.decode(ShulginRatingOption.self, forKey: .option)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(UInt64(creationDate.timeIntervalSince1970) * 1000, forKey: .creationDate)
        var timeInMillis: UInt64?
        if let time {
            timeInMillis = UInt64(time.timeIntervalSince1970) * 1000
        }
        try container.encode(timeInMillis, forKey: .time)
        try container.encode(option, forKey: .option)
    }
}
