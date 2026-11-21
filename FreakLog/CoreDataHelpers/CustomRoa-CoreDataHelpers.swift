import Foundation

extension CustomRoa {
  var administrationRouteUnwrapped: AdministrationRoute {
    AdministrationRoute(rawValue: administrationRoute ?? "") ?? .oral
  }

  // Custom substance roas may predate substanceName being set, so fall back to the parent's name.
  var substanceNameResolved: String? {
    substanceName ?? customSubstance?.name
  }

  var values: CustomRoaCodable {
    CustomRoaCodable(roa: self)
  }

  var roaDose: RoaDose? {
    values.roaDose(fallbackUnits: Self.fallbackUnits(
      substanceName: substanceNameResolved,
      route: administrationRouteUnwrapped,
      customSubstance: customSubstance
    ))
  }

  // Units used when doseUnits is blank: the custom substance's, else PsychonautWiki's for that route.
  static func fallbackUnits(substanceName: String?, route: AdministrationRoute, customSubstance: CustomSubstance?) -> String? {
    if let customSubstance {
      return customSubstance.units
    }
    return substanceName.flatMap { SubstanceRepo.shared.getSubstance(name: $0)?.getDose(for: route)?.units }
  }

  var roaDuration: RoaDuration? {
    values.roaDuration
  }

  var hasData: Bool {
    roaDose != nil || roaDuration != nil
  }
}
