import Foundation
import CryptoKit

// MARK: - Formulation

extension Formulation {
  static var previewSample: Formulation {
    FormulationCodable(
      name: "Party pill",
      note: "Pressed, tested",
      creationDate: .now,
      components: [
        .init(
          substanceName: "MDMA",
          administrationRoute: .oral,
          dose: 100,
          units: "mg",
          isEstimate: true,
          estimatedDoseStandardDeviation: 10),
        .init(
          substanceName: "Caffeine",
          administrationRoute: .oral,
          dose: 50,
          units: "mg",
          isEstimate: false,
          estimatedDoseStandardDeviation: nil),
      ]).insert(into: PersistenceController.preview.viewContext)
  }

  var nameUnwrapped: String {
    name ?? ""
  }

  var noteUnwrapped: String {
    note ?? ""
  }

  var creationDateUnwrapped: Date {
    creationDate ?? .now
  }

  var stableBlendIdentifier: UUID {
    if let blendIdentifier { return blendIdentifier }
    let digest = Array(SHA256.hash(data: Data(objectID.uriRepresentation().absoluteString.utf8)).prefix(16))
    return UUID(uuid: (
      digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], (digest[6] & 0x0f) | 0x80, digest[7],
      (digest[8] & 0x3f) | 0x80, digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
    ))
  }

  var includedProduct: FormulationCodable.IncludedProduct {
    .init(kind: .formulation, sourceIdentifier: stableBlendIdentifier,
          name: nameUnwrapped, unit: String(localized: "servings"), leaves: FormulationCodable(self).components)
  }

  var componentsUnwrapped: [FormulationComponent] {
    components?.allObjects as? [FormulationComponent] ?? []
  }

  // CloudKit can't sync ordered relationships, so components carry their position
  var componentsSorted: [FormulationComponent] {
    componentsUnwrapped.sorted { $0.position < $1.position }
  }

  // e.g. "100 mg MDMA oral, 50 mg Caffeine oral"
  var componentsDescription: String {
    componentsSorted.map { component in
      "\(component.doseDescription) \(component.substanceDisplayName) \(component.administrationRouteUnwrapped.rawValue)"
    }.joined(separator: ", ")
  }

  // The ingestions logged when taking the amount, linked to the formulation
  func ingestionArguments(amount: Double) -> [FinishIngestionScreenArguments] {
    FormulationCodable(self).ingestionArguments(amount: amount).map { arguments in
      var arguments = arguments
      arguments.formulation = self
      arguments.formulationAmount = amount
      return arguments
    }
  }

  func matches(searchText: String) -> Bool {
    guard !searchText.isEmpty else { return true }
    let search = searchText.lowercased()
    return nameUnwrapped.lowercased().contains(search)
      || noteUnwrapped.lowercased().contains(search)
      || componentsUnwrapped.contains { component in
        component.substanceNameUnwrapped.lowercased().contains(search)
          || component.substanceDisplayName.lowercased().contains(search)
          || component.blendPath.contains(where: { $0.name.lowercased().contains(search) })
      }
  }

}

// MARK: - FormulationComponent

extension FormulationComponent {
  var blendPath: [FormulationCodable.BlendLayer] {
    guard let blendPathData,
          let path = try? JSONDecoder().decode([FormulationCodable.BlendLayer].self, from: blendPathData),
          FormulationCodable.Component.isValid(blendPath: path) else { return [] }
    return path
  }
  var substanceNameUnwrapped: String {
    substanceName ?? ""
  }

  var substanceDisplayName: String {
    PersistenceController.shared.displayName(for: substanceNameUnwrapped)
  }

  var administrationRouteUnwrapped: AdministrationRoute {
    AdministrationRoute(rawValue: administrationRoute ?? "oral") ?? .oral
  }

  var doseUnwrapped: Double? {
    dose == 0 ? nil : dose
  }

  var unitsUnwrapped: String {
    units ?? ""
  }

  var estimatedDoseStandardDeviationUnwrapped: Double? {
    estimatedDoseStandardDeviation == 0 || !isEstimate ? nil : estimatedDoseStandardDeviation
  }

  var doseDescription: String {
    doseUnwrapped?.doseDescription(
      units: unitsUnwrapped,
      isEstimate: isEstimate,
      standardDeviation: estimatedDoseStandardDeviationUnwrapped) ?? "Unknown dose"
  }
}

extension CustomUnit {
  var includedProduct: FormulationCodable.IncludedProduct {
    .init(
      kind: .customUnit,
      sourceIdentifier: nil,
      name: nameUnwrapped,
      unit: pluralizableUnit.plural,
      leaves: [.init(substanceName: substanceNameUnwrapped, administrationRoute: administrationRouteUnwrapped,
                     dose: doseUnwrapped, units: originalUnitUnwrapped, isEstimate: isEstimate,
                     estimatedDoseStandardDeviation: estimatedDoseStandardDeviationUnwrapped)]
    )
  }
}
