import CoreData
import Foundation

struct SubstanceDataOverrideCodable: Codable {
  let substanceName: String
  let roas: [CustomRoaCodable]
}

extension SubstanceDataOverrideCodable {
  // Overrides are exported per substance; the store keeps one row per substance and route
  static func grouped(_ roas: [CustomRoa]) -> [SubstanceDataOverrideCodable] {
    Dictionary(grouping: roas) { $0.substanceName ?? "" }
      .filter { !$0.key.isEmpty }
      .map { name, roas in SubstanceDataOverrideCodable(substanceName: name, roas: roas.map(CustomRoaCodable.init(roa:))) }
  }

  func insert(into context: NSManagedObjectContext) {
    for roaCodable in roas {
      _ = roaCodable.insert(into: context, substanceName: substanceName)
    }
  }
}
