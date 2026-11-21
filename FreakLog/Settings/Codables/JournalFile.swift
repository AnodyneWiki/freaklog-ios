import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct JournalFile: FileDocument, Codable {
    static let readableContentTypes = [UTType.json]
    static let writableContentTypes = [UTType.json]
    var experiences: [ExperienceCodable]
    var substanceCompanions: [CompanionCodable]
    var customSubstances: [CustomSubstanceCodable]
    var customUnits: [CustomUnitCodable]
    var substanceDataOverrides: [SubstanceDataOverrideCodable]

    init(
        experiences: [Experience],
        customSubstances: [CustomSubstance],
        customUnits: [CustomUnit],
        substanceOverrideRoas: [CustomRoa] = [],
        substanceOverrides: [SubstanceOverride] = []
    ) {
        self.experiences = experiences.map(ExperienceCodable.init)
        // One color for each substance that was taken
        var substanceNames = Set<String>()
        substanceCompanions = experiences.flatMap(\.ingestionsSorted).compactMap { ingestion in
            guard substanceNames.insert(ingestion.substanceNameUnwrapped).inserted else { return nil }
            return CompanionCodable(substanceName: ingestion.substanceNameUnwrapped, color: ingestion.substanceColor)
        }
        self.customSubstances = customSubstances.map(CustomSubstanceCodable.init)
        self.customUnits = customUnits.map(CustomUnitCodable.init)
        substanceDataOverrides = SubstanceDataOverrideCodable.grouped(substanceOverrideRoas, overrides: substanceOverrides)
    }

    // Inserts everything in the file. The caller clears the journal before and saves after.
    func insert(into context: NSManagedObjectContext) {
        var companions: [String: SubstanceCompanion] = [:]
        for companionCodable in substanceCompanions where companions[companionCodable.substanceName] == nil {
            companions[companionCodable.substanceName] = companionCodable.insert(into: context)
        }
        var customUnitsById: [Int32: CustomUnit] = [:]
        for customUnitCodable in customUnits {
            customUnitsById[customUnitCodable.id] = customUnitCodable.insert(into: context)
        }
        for experienceCodable in experiences {
            _ = experienceCodable.insert(
                into: context,
                companion: { substanceName in
                    if let companion = companions[substanceName] {
                        return companion
                    }
                    let color = SubstanceColor.allCases.randomElement() ?? .red
                    let companion = CompanionCodable(substanceName: substanceName, color: color).insert(into: context)
                    companions[substanceName] = companion
                    return companion
                },
                customUnits: customUnitsById
            )
        }
        substanceDataOverrides.forEach { $0.insert(into: context) }
        customSubstances.forEach { _ = $0.insert(into: context) }
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            let decoder = JSONDecoder()
            self = try decoder.decode(Self.self, from: data)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return FileWrapper(regularFileWithContents: data)
    }



    enum CodingKeys: String, CodingKey {
        case experiences
        case substanceCompanions
        case customSubstances
        case customUnits
        case substanceDataOverrides
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        experiences = try values.decodeIfPresent([ExperienceCodable].self, forKey: .experiences) ?? []
        substanceCompanions = try values.decodeIfPresent([CompanionCodable].self, forKey: .substanceCompanions) ?? []
        customSubstances = try values.decodeIfPresent([CustomSubstanceCodable].self, forKey: .customSubstances) ?? []
        customUnits = try values.decodeIfPresent([CustomUnitCodable].self, forKey: .customUnits) ?? []
        substanceDataOverrides = try values.decodeIfPresent([SubstanceDataOverrideCodable].self, forKey: .substanceDataOverrides) ?? []
    }
}
