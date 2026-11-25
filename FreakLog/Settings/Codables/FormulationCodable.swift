import CoreData
import Foundation

// MARK: - FormulationCodable

// The value form of a formulation, used for editing, export and import. Components keep their order.
struct FormulationCodable: Codable, Hashable {
  // Each leaf keeps its actual dose and route. These layers describe how the leaf
  // was included without creating live links that could change an old recipe.
  struct BlendLayer: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case formulation, customUnit }

    let id: UUID
    let kind: Kind
    let sourceIdentifier: UUID?
    let name: String
    let unit: String
    var quantity: Double
  }

  struct IncludedProduct: Hashable {
    let kind: BlendLayer.Kind
    let sourceIdentifier: UUID?
    let name: String
    let unit: String
    let leaves: [Component]

    func leaves(quantity: Double, groupID: UUID = UUID()) -> [Component]? {
      guard quantity.isFinite, quantity > 0, !leaves.isEmpty, !name.isEmpty, !unit.isEmpty else { return nil }
      let layer = BlendLayer(
        id: groupID, kind: kind, sourceIdentifier: sourceIdentifier, name: name, unit: unit, quantity: quantity)
      let scaled = leaves.compactMap { leaf -> Component? in
        guard var leaf = leaf.scaled(by: quantity) else { return nil }
        leaf.id = UUID()
        leaf.blendPath.insert(layer, at: 0)
        return leaf
      }
      return scaled.count == leaves.count ? scaled : nil
    }
  }

  struct Component: Codable, Hashable, Identifiable {

    init(
      substanceName: String,
      administrationRoute: AdministrationRoute,
      dose: Double?,
      units: String,
      isEstimate: Bool,
      estimatedDoseStandardDeviation: Double?,
      isHiddenInTimeline: Bool = false)
    {
      self.substanceName = substanceName
      self.administrationRoute = administrationRoute
      self.dose = dose
      self.units = units
      self.isEstimate = isEstimate
      self.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation
      self.isHiddenInTimeline = isHiddenInTimeline
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
      isHiddenInTimeline = try values.decodeIfPresent(Bool.self, forKey: .isHiddenInTimeline) ?? false
      blendPath = try values.decodeIfPresent([BlendLayer].self, forKey: .blendPath) ?? []
      guard Self.isValid(blendPath: blendPath) else {
        throw DecodingError.dataCorruptedError(forKey: .blendPath, in: values, debugDescription: "Invalid formulation snapshot path")
      }
    }

    enum CodingKeys: String, CodingKey {
      case substanceName
      case administrationRoute
      case dose
      case units
      case isEstimate
      case estimatedDoseStandardDeviation
      case isHiddenInTimeline
      case blendPath
    }

    // Only tells components apart in lists while editing, so it isn't exported
    var id = UUID()
    var substanceName: String
    var administrationRoute: AdministrationRoute
    var dose: Double?
    var units: String
    var isEstimate: Bool
    var estimatedDoseStandardDeviation: Double?
    var isHiddenInTimeline: Bool
    var blendPath: [BlendLayer] = []

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(substanceName, forKey: .substanceName)
      try container.encode(administrationRoute.rawValue.uppercased(), forKey: .administrationRoute)
      try container.encode(dose, forKey: .dose)
      try container.encode(units, forKey: .units)
      try container.encode(isEstimate, forKey: .isEstimate)
      try container.encode(estimatedDoseStandardDeviation, forKey: .estimatedDoseStandardDeviation)
      try container.encodeIfPresent(isHiddenInTimeline ? true : nil, forKey: .isHiddenInTimeline)
      if !blendPath.isEmpty { try container.encode(blendPath, forKey: .blendPath) }
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
        estimatedDoseStandardDeviation: isEstimate ? estimatedDoseStandardDeviation.map { $0 * amount } : nil,
        isHiddenInTimeline: isHiddenInTimeline)
    }

    func scaled(by quantity: Double) -> Self? {
      guard quantity.isFinite, quantity > 0 else { return nil }
      var result = self
      if let dose {
        let scaled = dose * quantity
        guard scaled.isFinite, scaled != 0 || dose == 0 else { return nil }
        result.dose = scaled
      }
      if let deviation = estimatedDoseStandardDeviation {
        let scaled = deviation * quantity
        guard scaled.isFinite, scaled != 0 || deviation == 0 else { return nil }
        result.estimatedDoseStandardDeviation = scaled
      }
      return result
    }

    static func isValid(blendPath: [BlendLayer]) -> Bool {
      let identifiers = blendPath.compactMap(\.sourceIdentifier)
      return Set(blendPath.map(\.id)).count == blendPath.count
        && Set(identifiers).count == identifiers.count
        && blendPath.allSatisfy { $0.quantity.isFinite && $0.quantity > 0 && !$0.name.isEmpty && !$0.unit.isEmpty }
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
    case id
    case name
    case note
    case creationDate
    case components
    case blendIdentifier
  }

  var name: String
  var note: String
  var creationDate: Date
  var components: [Component]
  var id: String? = nil
  var blendIdentifier: UUID? = nil

  func canInclude(_ product: IncludedProduct) -> Bool {
    guard !product.leaves.isEmpty, !product.name.isEmpty, !product.unit.isEmpty,
          product.leaves.count + components.count < Int(Int16.max) else { return false }
    guard let blendIdentifier else { return true }
    return product.sourceIdentifier != blendIdentifier
      && !product.leaves.contains { $0.blendPath.contains { $0.sourceIdentifier == blendIdentifier } }
  }

  var substanceNames: [String] {
    components.map(\.substanceName).uniqued()
  }

  func ingestionArguments(amount: Double) -> [FinishIngestionScreenArguments] {
    guard components.allSatisfy({ $0.scaled(by: amount) != nil }) else { return [] }
    return components.map { $0.ingestionArguments(amount: amount) }
  }
}

extension FormulationCodable {
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    name = try values.decode(String.self, forKey: .name)
    note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
    creationDate = try values.decodeMillis(forKey: .creationDate)
    components = try values.decode([Component].self, forKey: .components)
    id = try values.decodeIfPresent(String.self, forKey: .id)
    blendIdentifier = try values.decodeIfPresent(UUID.self, forKey: .blendIdentifier)
    if let blendIdentifier, components.contains(where: { $0.blendPath.contains { $0.sourceIdentifier == blendIdentifier } }) {
      throw DecodingError.dataCorruptedError(forKey: .components, in: values, debugDescription: "Formulation includes itself")
    }
  }

  init(_ formulation: Formulation) {
    self.init(
      name: formulation.nameUnwrapped,
      note: formulation.noteUnwrapped,
      creationDate: formulation.creationDateUnwrapped,
      components: formulation.componentsSorted.map { component in
        var value = Component(
          substanceName: component.substanceNameUnwrapped,
          administrationRoute: component.administrationRouteUnwrapped,
          dose: component.doseUnwrapped,
          units: component.unitsUnwrapped,
          isEstimate: component.isEstimate,
          estimatedDoseStandardDeviation: component.estimatedDoseStandardDeviationUnwrapped,
          isHiddenInTimeline: component.isHiddenInTimeline)
        value.blendPath = component.blendPath
        return value
      },
      blendIdentifier: formulation.stableBlendIdentifier)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(note, forKey: .note)
    try container.encodeMillis(creationDate, forKey: .creationDate)
    try container.encode(components, forKey: .components)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(blendIdentifier, forKey: .blendIdentifier)
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
    formulation.blendIdentifier = blendIdentifier ?? formulation.blendIdentifier ?? UUID()
    let includedIdentities = Set(components.flatMap { $0.blendPath.compactMap(\.sourceIdentifier) })
    if !includedIdentities.isEmpty {
      let request = Formulation.fetchRequest()
      request.predicate = NSPredicate(format: "blendIdentifier == nil")
      if let legacyProducts = try? context.fetch(request) {
        for legacyProduct in legacyProducts where !legacyProduct.objectID.isTemporaryID {
          let identifier = legacyProduct.stableBlendIdentifier
          if includedIdentities.contains(identifier) { legacyProduct.blendIdentifier = identifier }
        }
      }
    }
    formulation.componentsUnwrapped.forEach(context.delete)
    for (position, value) in components.enumerated() {
      let component = FormulationComponent(context: context)
      component.position = Int16(clamping: position)
      component.substanceName = value.substanceName
      component.administrationRoute = value.administrationRoute.rawValue
      component.dose = value.dose ?? 0
      component.units = value.units
      component.isEstimate = value.isEstimate
      component.isHiddenInTimeline = value.isHiddenInTimeline
      component.estimatedDoseStandardDeviation = value.estimatedDoseStandardDeviation ?? 0
      component.blendPathData = value.blendPath.isEmpty ? nil : try? JSONEncoder().encode(value.blendPath)
      component.formulation = formulation
    }
  }
}
