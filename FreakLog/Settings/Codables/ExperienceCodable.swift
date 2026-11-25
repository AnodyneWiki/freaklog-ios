import CoreData
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
        location = experienceLocation.map(LocationCodable.init)
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
        let explicitSortDate = try values.decodeMillisIfPresent(forKey: .sortDate)
        isFavorite = try (values.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false
        let ingestionCodables = try values.decodeIfPresent([IngestionCodable].self, forKey: .ingestions) ?? []
        ingestions = ingestionCodables
        sortDate = explicitSortDate ?? ingestionCodables.map(\.time).min()
        if let date = try values.decodeMillisIfPresent(forKey: .creationDate) ?? sortDate {
            creationDate = date
        } else {
            creationDate = try values.decodeMillis(forKey: .creationDate)
        }
        ratings = try (values.decodeIfPresent([RatingCodable].self, forKey: .ratings)) ?? []
        timedNotes = try (values.decodeIfPresent([TimedNoteCodable].self, forKey: .timedNotes)) ?? []
        location = try values.decodeIfPresent(LocationCodable.self, forKey: .location)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encodeMillis(creationDate, forKey: .creationDate)
        try container.encodeMillis(sortDate ?? creationDate, forKey: .sortDate)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(ratings, forKey: .ratings)
        try container.encode(timedNotes, forKey: .timedNotes)
        try container.encode(ingestions, forKey: .ingestions)
        try container.encode(location, forKey: .location)
    }
}

extension ExperienceCodable {
    init(_ experience: Experience, formulationIds: [NSManagedObjectID: String]) {
        self.init(
            title: experience.titleUnwrapped,
            text: experience.textUnwrapped,
            creationDate: experience.creationDateUnwrapped,
            sortDate: experience.sortDate,
            isFavorite: experience.isFavorite,
            ingestions: experience.ingestionsSorted.map { ingestion in
                var record = IngestionCodable(ingestion)
                record.formulationId = ingestion.formulation.flatMap { formulationIds[$0.objectID] }
                return record
            },
            ratings: experience.ratingsUnwrapped.map(RatingCodable.init),
            timedNotes: experience.timedNotesSorted.map(TimedNoteCodable.init),
            experienceLocation: experience.legacyLocation
        )
    }

    // Inserts the experience with its ingestions, ratings and timed notes
    func insert(
        into context: NSManagedObjectContext,
        companion: (String) -> SubstanceCompanion,
        customUnits: [Int32: CustomUnit],
        formulationsById: [String: Formulation],
        formulationsByName: [String: Formulation]
    ) -> Experience {
        let experience = Experience(context: context)
        experience.title = title
        experience.text = text
        experience.creationDate = creationDate
        experience.sortDate = sortDate
        experience.isFavorite = isFavorite
        for ingestionCodable in ingestions {
            let ingestion = ingestionCodable.insert(into: context, fallbackLocation: location)
            ingestion.substanceCompanion = companion(ingestionCodable.substanceName)
            ingestion.customUnit = ingestionCodable.customUnitId.flatMap { customUnits[$0] }
            if let id = ingestionCodable.formulationId {
                ingestion.formulation = formulationsById[id]
            } else {
                ingestion.formulation = ingestionCodable.formulationName.flatMap { formulationsByName[$0] }
            }
            experience.addToIngestions(ingestion)
        }
        for ratingCodable in ratings {
            ratingCodable.insert(into: context, fallbackDate: creationDate).experience = experience
        }
        for timedNoteCodable in timedNotes {
            timedNoteCodable.insert(into: context).experience = experience
        }
        if let location {
            experience.legacyLocation = ExperienceLocation.make(from: location, in: context)
        }
        return experience
    }
}
