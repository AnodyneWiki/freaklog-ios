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

  // Falls back to the parent custom substance's units if doseUnits is blank.
  var roaDose: RoaDose? {
    values.roaDose(fallbackUnits: customSubstance?.units)
  }

  var roaDuration: RoaDuration? {
    values.roaDuration
  }

  var hasData: Bool {
    roaDose != nil || roaDuration != nil
  }
}
