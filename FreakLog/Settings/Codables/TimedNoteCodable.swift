import CoreData
import Foundation

struct TimedNoteCodable: Codable {
    let creationDate: Date
    let time: Date
    let note: String
    let color: SubstanceColor
    let isPartOfTimeline: Bool

    init(creationDate: Date, time: Date, note: String, color: SubstanceColor, isPartOfTimeline: Bool) {
        self.creationDate = creationDate
        self.time = time
        self.note = note
        self.color = color
        self.isPartOfTimeline = isPartOfTimeline
    }

    enum CodingKeys: String, CodingKey {
        case creationDate
        case time
        case note
        case color
        case isPartOfTimeline
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let creationDateMillis = try values.decode(UInt64.self, forKey: .creationDate)
        creationDate = getDateFromMillis(millis: creationDateMillis)
        let timeMillis = try values.decode(UInt64.self, forKey: .time)
        time = getDateFromMillis(millis: timeMillis)
        note = try values.decode(String.self, forKey: .note)
        color = try values.decode(SubstanceColor.self, forKey: .color)
        isPartOfTimeline = try values.decode(Bool.self, forKey: .isPartOfTimeline)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(UInt64(creationDate.timeIntervalSince1970) * 1000, forKey: .creationDate)
        try container.encode(UInt64(time.timeIntervalSince1970) * 1000, forKey: .time)
        try container.encode(note, forKey: .note)
        try container.encode(color.rawValue.uppercased(), forKey: .color)
        try container.encode(isPartOfTimeline, forKey: .isPartOfTimeline)
    }
}

extension TimedNoteCodable {
    init(_ timedNote: TimedNote) {
        self.init(
            creationDate: timedNote.creationDateUnwrapped,
            time: timedNote.timeUnwrapped,
            note: timedNote.noteUnwrapped,
            color: timedNote.color,
            isPartOfTimeline: timedNote.isPartOfTimeline
        )
    }

    func insert(into context: NSManagedObjectContext) -> TimedNote {
        let timedNote = TimedNote(context: context)
        timedNote.creationDate = creationDate
        timedNote.time = time
        timedNote.note = note
        timedNote.colorAsText = color.rawValue
        timedNote.isPartOfTimeline = isPartOfTimeline
        return timedNote
    }
}
