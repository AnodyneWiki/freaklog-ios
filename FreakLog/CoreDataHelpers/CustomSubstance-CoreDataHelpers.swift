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
}
