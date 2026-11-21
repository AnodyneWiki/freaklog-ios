import CoreData
import Foundation

struct CompanionCodable: Codable {
    let substanceName: String
    let color: SubstanceColor

    enum CodingKeys: String, CodingKey {
        case substanceName
        case color
    }

    init(substanceName: String, color: SubstanceColor) {
        self.substanceName = substanceName
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try values.decode(String.self, forKey: .substanceName)
        color = try values.decode(SubstanceColor.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(substanceName, forKey: .substanceName)
        try container.encode(color.rawValue, forKey: .color)
    }
}

extension CompanionCodable {
    func insert(into context: NSManagedObjectContext) -> SubstanceCompanion {
        let companion = SubstanceCompanion(context: context)
        companion.substanceName = substanceName
        companion.colorAsText = color.rawValue
        return companion
    }
}
