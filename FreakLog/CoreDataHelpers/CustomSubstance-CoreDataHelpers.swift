import Foundation

extension CustomSubstance {
  var nameUnwrapped: String {
    name ?? "Unknown"
  }

  var unitsUnwrapped: String {
    units ?? ""
  }

  var explanationUnwrapped: String {
    explanation ?? ""
  }

  var customRoasSorted: [CustomRoa] {
    let roas = customRoas as? Set<CustomRoa> ?? []
    return roas.sorted { $0.administrationRouteUnwrapped.rawValue < $1.administrationRouteUnwrapped.rawValue }
  }

  func getRoa(for route: AdministrationRoute) -> CustomRoa? {
    customRoasSorted.first { $0.administrationRouteUnwrapped == route }
  }

  func getRoaDose(for route: AdministrationRoute) -> RoaDose? {
    getRoa(for: route)?.roaDose
  }

  func getRoaDuration(for route: AdministrationRoute) -> RoaDuration? {
    getRoa(for: route)?.roaDuration
  }
}
