import CoreData
import Foundation

// The user's changes to one substance: dose and duration per route, and its display name and categories.
// Older files only have roas.
struct SubstanceDataOverrideCodable: Codable {
  let substanceName: String
  let roas: [CustomRoaCodable]
  var displayName: String?
  var categories: [String]?
  var personalTags: PersonalSubstanceTags?

  init(
    substanceName: String, roas: [CustomRoaCodable], displayName: String? = nil, categories: [String]? = nil,
    personalTags: PersonalSubstanceTags? = nil
  ) {
    self.substanceName = substanceName
    self.roas = roas
    self.displayName = displayName
    self.categories = categories
    self.personalTags = personalTags
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    substanceName = try container.decode(String.self, forKey: .substanceName)
    roas = try container.decodeIfPresent([CustomRoaCodable].self, forKey: .roas) ?? []
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    categories = try container.decodeIfPresent([String].self, forKey: .categories)
    personalTags = try container.decodeIfPresent(PersonalSubstanceTags.self, forKey: .personalTags)
  }
}

extension SubstanceDataOverrideCodable {
  // One entry per substance; the store keeps one roa row per substance and route, and override rows that
  // iCloud duplicated are merged so no device's values are lost
  static func grouped(_ roas: [CustomRoa], overrides: [SubstanceOverride]) -> [SubstanceDataOverrideCodable] {
    let roasByName = Dictionary(grouping: roas) { $0.substanceName ?? "" }
    let overridesByName = Dictionary(overrides.map { ($0.substanceName ?? "", $0.entry) }) { $0.merged($1) }
    let names = Set(roasByName.keys).union(overridesByName.keys).filter { !$0.isEmpty }
    return names.sorted().map { name in
      let entry = overridesByName[name]
      let tags = entry?.tags ?? PersonalSubstanceTags()
      return SubstanceDataOverrideCodable(
        substanceName: name,
        roas: (roasByName[name] ?? []).map(CustomRoaCodable.init(roa:)),
        displayName: entry?.displayName,
        categories: entry?.categories,
        personalTags: tags.names.isEmpty ? nil : tags
      )
    }
  }

  func insert(into context: NSManagedObjectContext) {
    for roaCodable in roas {
      _ = roaCodable.insert(into: context, substanceName: substanceName)
    }
    if displayName != nil || categories != nil || personalTags?.names.isEmpty == false {
      let override = SubstanceOverride(context: context)
      override.substanceName = substanceName
      override.displayName = displayName
      override.categoryList = categories
      override.personalTags = personalTags ?? PersonalSubstanceTags()
    }
  }
}
