import CoreData
import Foundation

// MARK: - FormulationCodable

// The value form of a formulation, used for editing, export and import. Components keep their order.
struct FormulationCodable: Codable, Hashable {
  struct Component: Codable, Hashable, Identifiable {

    init(
      substanceName: String,
      administrationRoute: AdministrationRoute,
      dose: Double?,
      units: String,
      isEstimate: Bool,
      estimatedDoseStandardDeviation: Double?)
    {
      self.substanceName = substanceName
      self.administrationRoute = administrationRoute
      self.dose = dose
      self.units = units
      self.isEstimate = isEstimate
      self.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      substanceName = try values.decode(String.self, forKey: .substanceName)
      let routeString = try values.decode(String.self, forKey: .administrationRoute)
      guard let route = AdministrationRoute(rawValue: routeString.lowercased()) else {
        throw DecodingError.dataCorruptedError(
          forKey: .administrationRoute,
          in: values,
          debugDescription: "\(routeString) is not a valid route")
      }
      administrationRoute = route
      dose = try values.decodeIfPresent(Double.self, forKey: .dose)
      units = try values.decode(String.self, forKey: .units)
      isEstimate = try values.decode(Bool.self, forKey: .isEstimate)
      estimatedDoseStandardDeviation = try values.decodeIfPresent(Double.self, forKey: .estimatedDoseStandardDeviation)
    }

    enum CodingKeys: String, CodingKey {
      case substanceName
      case administrationRoute
      case dose
      case units
      case isEstimate
      case estimatedDoseStandardDeviation
    }

    // Only tells components apart in lists while editing, so it isn't exported
    var id = UUID()
    var substanceName: String
    var administrationRoute: AdministrationRoute
    var dose: Double?
    var units: String
    var isEstimate: Bool
    var estimatedDoseStandardDeviation: Double?

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(substanceName, forKey: .substanceName)
      try container.encode(administrationRoute.rawValue.uppercased(), forKey: .administrationRoute)
      try container.encode(dose, forKey: .dose)
      try container.encode(units, forKey: .units)
      try container.encode(isEstimate, forKey: .isEstimate)
      try container.encode(estimatedDoseStandardDeviation, forKey: .estimatedDoseStandardDeviation)
    }

    // The ingestion of this component when taking the given amount of the formulation. The amount is exact,
    // so the deviation scales with it, like for custom units.
    func ingestionArguments(amount: Double) -> FinishIngestionScreenArguments {
      FinishIngestionScreenArguments(
        substanceName: substanceName,
        administrationRoute: administrationRoute,
        dose: dose.map { $0 * amount },
        units: units,
        isEstimate: isEstimate,
        estimatedDoseStandardDeviation: isEstimate ? estimatedDoseStandardDeviation.map { $0 * amount } : nil)
    }

    func doseDescription(amount: Double = 1) -> String {
      let arguments = ingestionArguments(amount: amount)
      return arguments.dose?.doseDescription(
        units: units,
        isEstimate: isEstimate,
        standardDeviation: arguments.estimatedDoseStandardDeviation,
        rounded: true) ?? "Unknown dose"
    }
  }

  enum CodingKeys: String, CodingKey {
    case name
    case note
    case creationDate
    case components
  }

  var name: String
  var note: String
  var creationDate: Date
  var components: [Component]

  var substanceNames: [String] {
    components.map(\.substanceName).uniqued()
  }

  func ingestionArguments(amount: Double) -> [FinishIngestionScreenArguments] {
    components.map { $0.ingestionArguments(amount: amount) }
  }
}

extension FormulationCodable {
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    name = try values.decode(String.self, forKey: .name)
    note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
    creationDate = try values.decodeMillis(forKey: .creationDate)
    components = try values.decode([Component].self, forKey: .components)
  }

  init(_ formulation: Formulation) {
    self.init(
      name: formulation.nameUnwrapped,
      note: formulation.noteUnwrapped,
      creationDate: formulation.creationDateUnwrapped,
      components: formulation.componentsSorted.map { component in
        Component(
          substanceName: component.substanceNameUnwrapped,
          administrationRoute: component.administrationRouteUnwrapped,
          dose: component.doseUnwrapped,
          units: component.unitsUnwrapped,
          isEstimate: component.isEstimate,
          estimatedDoseStandardDeviation: component.estimatedDoseStandardDeviationUnwrapped)
      })
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(note, forKey: .note)
    try container.encodeMillis(creationDate, forKey: .creationDate)
    try container.encode(components, forKey: .components)
  }

  @discardableResult
  func insert(into context: NSManagedObjectContext) -> Formulation {
    let formulation = Formulation(context: context)
    apply(to: formulation)
    return formulation
  }

  // Replaces the formulation's values and components with these
  func apply(to formulation: Formulation) {
    guard let context = formulation.managedObjectContext else { return }
    formulation.name = name
    formulation.note = note
    formulation.creationDate = creationDate
    formulation.componentsUnwrapped.forEach(context.delete)
    for (position, value) in components.enumerated() {
      let component = FormulationComponent(context: context)
      component.position = Int16(clamping: position)
      component.substanceName = value.substanceName
      component.administrationRoute = value.administrationRoute.rawValue
      component.dose = value.dose ?? 0
      component.units = value.units
      component.isEstimate = value.isEstimate
      component.estimatedDoseStandardDeviation = value.estimatedDoseStandardDeviation ?? 0
      component.formulation = formulation
    }
  }
}
