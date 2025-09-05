import Foundation

struct ExperienceCodable: Codable {
    let title: String
    let text: String
    let creationDate: Date
    let sortDate: Date?
    let isFavorite: Bool
    let ingestions: [IngestionCodable]
    let ratings: [RatingCodable]
    let timedNotes: [TimedNoteCodable]
    let location: LocationCodable?

    init(
        title: String,
        text: String,
        creationDate: Date,
        sortDate: Date?,
        isFavorite: Bool,
        ingestions: [IngestionCodable],
        ratings: [RatingCodable],
        timedNotes: [TimedNoteCodable],
        experienceLocation: ExperienceLocation?
    ) {
        self.title = title
        self.text = text
        self.creationDate = creationDate
        self.sortDate = sortDate
        self.isFavorite = isFavorite
        self.ingestions = ingestions
        self.ratings = ratings
        self.timedNotes = timedNotes
        if let experienceLocation {
            location = LocationCodable(
                name: experienceLocation.nameUnwrapped,
                latitude: experienceLocation.latitudeUnwrapped,
                longitude: experienceLocation.longitudeUnwrapped
            )
        } else {
            location = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case title
        case text
        case creationDate
        case sortDate
        case isFavorite
        case ingestions
        case ratings
        case timedNotes
        case location
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        text = try values.decode(String.self, forKey: .text)
        let creationDateMillis = try values.decode(UInt64.self, forKey: .creationDate)
        creationDate = getDateFromMillis(millis: creationDateMillis)
        isFavorite = try (values.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false
        let ingestionCodables = try values.decodeIfPresent([IngestionCodable].self, forKey: .ingestions) ?? []
        ingestions = ingestionCodables
        if let sortDateMillis = try values.decodeIfPresent(UInt64.self, forKey: .sortDate) {
            sortDate = getDateFromMillis(millis: sortDateMillis)
        } else {
            sortDate = ingestionCodables.map { $0.time }.min()
        }
        ratings = try (values.decodeIfPresent([RatingCodable].self, forKey: .ratings)) ?? []
        timedNotes = try (values.decodeIfPresent([TimedNoteCodable].self, forKey: .timedNotes)) ?? []
        location = try values.decodeIfPresent(LocationCodable.self, forKey: .location)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(UInt64(creationDate.timeIntervalSince1970) * 1000, forKey: .creationDate)
        if let sortDate {
            try container.encode(UInt64(sortDate.timeIntervalSince1970) * 1000, forKey: .sortDate)
        } else {
            let sortMillis: UInt64? = nil
            try container.encode(sortMillis, forKey: .sortDate)
        }
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(timedNotes, forKey: .timedNotes)
        try container.encode(ingestions, forKey: .ingestions)
        try container.encode(location, forKey: .location)
    }
}
