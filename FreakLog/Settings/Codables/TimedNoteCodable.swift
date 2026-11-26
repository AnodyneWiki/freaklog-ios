import CoreData
import Foundation

struct TimedNoteCodable: Codable {
    let creationDate: Date
    let time: Date
    let note: String
    let color: SubstanceColor
    let isPartOfTimeline: Bool
    let details: TimedNoteDetails

    init(
        creationDate: Date, time: Date, note: String, color: SubstanceColor,
        isPartOfTimeline: Bool, details: TimedNoteDetails = .init()
    ) {
        self.creationDate = creationDate
        self.time = time
        self.note = note
        self.color = color
        self.isPartOfTimeline = isPartOfTimeline
        self.details = details
    }

    enum CodingKeys: String, CodingKey {
        case creationDate
        case time
        case note
        case color
        case colorHex
        case isPartOfTimeline
        case mood
        case energy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try values.decodeMillis(forKey: .creationDate)
        time = try values.decodeMillis(forKey: .time)
        note = try values.decode(String.self, forKey: .note)
        color = try values.decodeIfPresent(SubstanceColor.self, forKey: .colorHex)
            ?? values.decode(SubstanceColor.self, forKey: .color)
        isPartOfTimeline = try values.decode(Bool.self, forKey: .isPartOfTimeline)
        details = TimedNoteDetails(
            mood: try values.decodeIfPresent(String.self, forKey: .mood).flatMap(TimedNoteMood.init(rawValue:)),
            energy: try values.decodeIfPresent(String.self, forKey: .energy).flatMap(TimedNoteEnergy.init(rawValue:))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeMillis(creationDate, forKey: .creationDate)
        try container.encodeMillis(time, forKey: .time)
        try container.encode(note, forKey: .note)
        try container.encode(color.exportValue, forKey: .color)
        try container.encodeIfPresent(color.isInPalette ? nil : color.rawValue, forKey: .colorHex)
        try container.encode(isPartOfTimeline, forKey: .isPartOfTimeline)
        try container.encodeIfPresent(details.mood?.rawValue, forKey: .mood)
        try container.encodeIfPresent(details.energy?.rawValue, forKey: .energy)
    }
}

extension TimedNoteCodable {
    init(_ timedNote: TimedNote) {
        self.init(
            creationDate: timedNote.creationDateUnwrapped,
            time: timedNote.timeUnwrapped,
            note: timedNote.noteUnwrapped,
            color: timedNote.color,
            isPartOfTimeline: timedNote.isPartOfTimeline,
            details: timedNote.details
        )
    }

    func insert(into context: NSManagedObjectContext) -> TimedNote {
        let timedNote = TimedNote(context: context)
        timedNote.creationDate = creationDate
        timedNote.time = time
        timedNote.note = note
        timedNote.colorAsText = color.rawValue
        timedNote.isPartOfTimeline = isPartOfTimeline
        timedNote.details = details
        return timedNote
    }
}
