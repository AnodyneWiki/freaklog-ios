import CoreData
import Foundation

struct CompanionCodable: Codable {
    let substanceName: String
    let color: SubstanceColor
    let isHiddenInTimeline: Bool

    enum CodingKeys: String, CodingKey {
        case substanceName
        case color
        case colorHex
        case isHiddenInTimeline
    }

    init(substanceName: String, color: SubstanceColor, isHiddenInTimeline: Bool = false) {
        self.substanceName = substanceName
        self.color = color
        self.isHiddenInTimeline = isHiddenInTimeline
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try values.decode(String.self, forKey: .substanceName)
        color = try values.decodeIfPresent(SubstanceColor.self, forKey: .colorHex)
            ?? values.decode(SubstanceColor.self, forKey: .color)
        isHiddenInTimeline = try values.decodeIfPresent(Bool.self, forKey: .isHiddenInTimeline) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(substanceName, forKey: .substanceName)
        try container.encode(color.exportValue, forKey: .color)
        try container.encodeIfPresent(color.isInPalette ? nil : color.rawValue, forKey: .colorHex)
        try container.encodeIfPresent(isHiddenInTimeline ? true : nil, forKey: .isHiddenInTimeline)
    }
}

extension CompanionCodable {
    func insert(into context: NSManagedObjectContext) -> SubstanceCompanion {
        let companion = SubstanceCompanion(context: context)
        companion.substanceName = substanceName
        companion.colorAsText = color.rawValue
        companion.isHiddenInTimeline = isHiddenInTimeline
        return companion
    }
}
