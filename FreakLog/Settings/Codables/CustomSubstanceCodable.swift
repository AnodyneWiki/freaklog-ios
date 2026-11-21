import CoreData
import Foundation

struct CustomSubstanceCodable: Codable {
  let name: String
  let units: String
  let description: String
  let roas: [CustomRoaCodable]

  init(name: String, units: String, description: String, roas: [CustomRoaCodable] = []) {
    self.name = name
    self.units = units
    self.description = description
    self.roas = roas
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    units = try container.decode(String.self, forKey: .units)
    description = try container.decode(String.self, forKey: .description)
    roas = try container.decodeIfPresent([CustomRoaCodable].self, forKey: .roas) ?? []
  }
}

extension CustomSubstanceCodable {
  init(_ customSubstance: CustomSubstance) {
    self.init(
      name: customSubstance.nameUnwrapped,
      units: customSubstance.unitsUnwrapped,
      description: customSubstance.explanationUnwrapped,
      roas: customSubstance.customRoasSorted.map(CustomRoaCodable.init(roa:))
    )
  }

  // Inserts the substance with its dose and duration data
  func insert(into context: NSManagedObjectContext) -> CustomSubstance {
    let customSubstance = CustomSubstance(context: context)
    customSubstance.name = name
    customSubstance.units = units
    customSubstance.explanation = description
    for roaCodable in roas {
      roaCodable.insert(into: context, substanceName: name).customSubstance = customSubstance
    }
    return customSubstance
  }
}
