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
