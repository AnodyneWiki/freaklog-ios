import Foundation

struct EverythingForOneTimedNote: Codable, Equatable {
    static func == (lhs: EverythingForOneTimedNote, rhs: EverythingForOneTimedNote) -> Bool {
        lhs.time == rhs.time
    }

    let time: Date
    let color: SubstanceColor
}
