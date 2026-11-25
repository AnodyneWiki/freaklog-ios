import CoreData
import UIKit

// MARK: - WatchQuickLogError

enum WatchQuickLogError: LocalizedError {
  case customUnitMissing
  case invalidUndo

  var errorDescription: String? {
    switch self {
    case .customUnitMissing:
      "This unit was deleted on your iPhone"
    case .invalidUndo:
      "The watch undo request couldn't be read"
    }
  }
}

// MARK: - WatchQuickLogging

// The journal side of the watch app: the quick log suggestions it shows, and logging what it sends
// the way the add ingestion screens do, with the default experience, color, webhooks and live activity.
// Formulations never logged yet come last, as they have no recent use to sort by.
@MainActor
enum WatchQuickLogging {
  private static let undos = WatchUndoJournal(file: URL.applicationSupportDirectory.appendingPathComponent("WatchUndos.json"))

  static func suggestions() -> [WatchSuggestion] {
    let persistence = PersistenceController.shared
    let suggestions = getSuggestions(
      sortedIngestions: persistence.getRecentIngestions(limit: 1000),
      customUnits: [])
    let suggestedFormulations = Set(suggestions.compactMap { ($0 as? FormulationSuggestions)?.formulation })
    let unusedFormulations = persistence.getAllFormulations().filter { !suggestedFormulations.contains($0) }.map {
      watchSuggestion($0, amounts: [1, 2])
    }
    return suggestions.prefix(maxNumberOfSuggestions).compactMap { suggestion in
      switch suggestion {
      case let pure as PureSubstanceSuggestions:
        watchSuggestion(
          id: pure.id,
          substanceName: pure.substance.name,
          route: pure.route,
          color: pure.substanceColor,
          dosesAndUnit: pure.dosesAndUnit)
      case let custom as CustomSubstanceSuggestions:
        watchSuggestion(
          id: custom.id,
          substanceName: custom.customSubstanceName,
          route: custom.administrationRoute,
          color: custom.substanceColor,
          dosesAndUnit: custom.dosesAndUnit)
      case let unit as CustomUnitSuggestions:
        watchSuggestion(unit)
      case let formulation as FormulationSuggestions:
        watchSuggestion(formulation.formulation, amounts: formulation.amounts)
      default:
        nil
      }
    } + unusedFormulations
  }

  // Logging the same request twice, e.g. once as a message and again as a queued transfer, adds it once
  // A formulation is logged as it was when sent, with an ingestion for each of its components
  static func log(_ request: WatchLogRequest) throws {
    guard try !undos.contains(request.id) else { return }
    let persistence = PersistenceController.shared
    let context = persistence.viewContext
    let identifiers = request.ingestionIdentifiers
    guard try context.count(for: PersistenceController.ingestionsRequest(withIdentifiers: identifiers)) == 0 else { return }
    let suggestion = request.suggestion
    var customUnit: CustomUnit?
    if let unitID = suggestion.customUnit?.id {
      guard let unit: CustomUnit = existingObject(uri: unitID, in: context) else { throw WatchQuickLogError.customUnitMissing }
      customUnit = unit
    }
    // Logged as it was sent even if the formulation was deleted since, then without the link
    let formulation: Formulation? = suggestion.formulation == nil ? nil : existingObject(uri: suggestion.id, in: context)
    let closestExperience = ExperienceLogic.closestExperience(
      from: persistence.getExperiences(near: request.time),
      to: request.time)
    let experience = closestExperience ?? Experience.create(at: request.time, in: context)

    let parts: [(substanceName: String, route: String, units: String, dose: WatchDose)] =
      if let formulation = suggestion.formulation, let amount = request.dose.amount {
        formulation.components.map { ($0.substanceName, $0.route, $0.units, $0.dose(for: amount)) }
      } else {
        [(suggestion.substanceName, suggestion.route, suggestion.units, request.dose)]
      }
    var companions: [String: SubstanceCompanion] = [:]
    let ingestions = zip(identifiers, parts).map { identifier, part in
      let companion = companions[part.substanceName] ?? companion(for: part.substanceName, in: context)
      companions[part.substanceName] = companion
      let ingestion = Ingestion(context: context)
      ingestion.identifier = identifier
      ingestion.time = request.time
      ingestion.creationDate = Date()
      ingestion.customUnit = customUnit
      if suggestion.formulation != nil {
        ingestion.formulation = formulation
        ingestion.formulationAmount = request.dose.amount ?? 0
      }
      ingestion.dose = part.dose.amount ?? 0
      ingestion.units = part.units
      ingestion.isEstimate = part.dose.isEstimate
      ingestion.estimatedDoseStandardDeviation = part.dose.standardDeviation ?? 0
      ingestion.note = ""
      ingestion.administrationRoute = part.route
      ingestion.substanceName = part.substanceName
      ingestion.color = companion.colorAsText
      ingestion.experience = experience
      ingestion.substanceCompanion = companion
      return ingestion
    }
    try IngestionSaving.save(ingestions, sendingWebhooksTo: WebhookPreset.defaultPresetObjectIDs())

    let defaults = UserDefaults.standard
    let wantsLiveActivity = defaults
      .object(forKey: PersistenceController.shouldAutomaticallyStartLiveActivityKey) as? Bool ?? true
    if
      #available(iOS 16.2, *), closestExperience == nil, wantsLiveActivity, LiveActivities.areAvailable,
      !ActivityManager.shared.isActivityActive, experience.isCurrent
    {
      Task {
        await ActivityManager.shared.show(experience)
      }
    }
  }

  static func undo(ingestionsWithIdentifiers identifiers: [UUID]) async throws {
    try await undos.undo(identifiers, delete: deleteUndoneIngestions)
  }

  static func retryPendingUndos() async {
    do {
      for identifiers in try undos.pending() {
        do {
          try await undo(ingestionsWithIdentifiers: identifiers)
        } catch {
          print("Retrying watch undo failed: \(error)")
        }
      }
    } catch {
      print("Could not read pending watch undos: \(error)")
    }
  }

  private static func deleteUndoneIngestions(_ identifiers: [UUID]) async throws {
    let persistence = PersistenceController.shared
    let ingestions = try persistence.viewContext.fetch(PersistenceController.ingestionsRequest(withIdentifiers: identifiers))
    guard !ingestions.isEmpty else { return }
    let cleanUp = await IngestionDeletion.remoteCleanUp(for: ingestions)
    // Save in a dedicated context so a failed undo cannot commit or roll back unrelated edits.
    try await persistence.container.performBackgroundTask { context in
      try saveUndoDeletion(identifiers, in: context)
    }
    cleanUp()
  }

  // Also deletes the experience when these are its only ingestions and it has no notes or ratings.
  nonisolated static func saveUndoDeletion(_ identifiers: [UUID], in context: NSManagedObjectContext) throws {
    let ingestions = try context.fetch(PersistenceController.ingestionsRequest(withIdentifiers: identifiers))
    guard !ingestions.isEmpty else { return }
    if let experience = ingestions.first?.experience,
      Set(experience.ingestionsSorted) == Set(ingestions),
      experience.timedNotesSorted.isEmpty, experience.ratingsUnwrapped.isEmpty, (experience.text ?? "").isEmpty
    {
      context.delete(experience)
    } else {
      ingestions.forEach(context.delete)
    }
    try context.save()
  }

  private static let maxNumberOfSuggestions = 30

  // MARK: - Suggestions

  private static func watchSuggestion(
    id: String,
    substanceName: String,
    route: AdministrationRoute,
    color: SubstanceColor,
    dosesAndUnit: [RegularDoseAndUnit])
    -> WatchSuggestion?
  {
    // A suggestion shows one unit, the latest one used
    guard let units = dosesAndUnit.first?.units else { return nil }
    return WatchSuggestion(
      id: id,
      substanceName: substanceName,
      displayName: PersistenceController.shared.displayName(for: substanceName),
      route: route.rawValue,
      color: watchColor(color),
      units: units,
      customUnit: nil,
      doses: dosesAndUnit.filter { $0.units == units }.map {
        WatchDose(amount: $0.dose, isEstimate: $0.isEstimate, standardDeviation: $0.estimatedDoseStandardDeviation)
      })
  }

  private static func watchSuggestion(_ suggestion: CustomUnitSuggestions) -> WatchSuggestion {
    let unit = suggestion.customUnit
    return WatchSuggestion(
      id: suggestion.id,
      substanceName: unit.substanceNameUnwrapped,
      displayName: unit.substanceDisplayName,
      route: unit.administrationRouteUnwrapped.rawValue,
      color: watchColor(suggestion.substanceColor),
      units: unit.originalUnitUnwrapped,
      customUnit: WatchCustomUnit(
        id: unit.objectID.uriRepresentation().absoluteString,
        name: unit.nameUnwrapped,
        singular: unit.pluralizableUnit.singular,
        plural: unit.pluralizableUnit.plural,
        dosePerUnit: unit.doseUnwrapped,
        isEstimate: unit.isEstimate),
      doses: suggestion.doses.map {
        WatchDose(amount: $0.dose, isEstimate: $0.isEstimate, standardDeviation: $0.estimatedStandardDeviation)
      })
  }

  // Its doses are amounts of the formulation
  private static func watchSuggestion(_ formulation: Formulation, amounts: [Double]) -> WatchSuggestion {
    let components = formulation.componentsSorted
    let routes = Set(components.map(\.administrationRouteUnwrapped))
    return WatchSuggestion(
      id: formulation.objectID.uriRepresentation().absoluteString,
      substanceName: formulation.nameUnwrapped,
      displayName: formulation.nameUnwrapped,
      route: routes.count == 1 ? routes.first?.rawValue ?? "" : "",
      color: watchColor(getColor(for: components.first?.substanceNameUnwrapped ?? "")),
      units: "",
      customUnit: nil,
      doses: amounts.map { WatchDose(amount: $0, isEstimate: false, standardDeviation: nil) },
      formulation: WatchFormulation(components: components.map { component in
        WatchFormulationComponent(
          substanceName: component.substanceNameUnwrapped,
          displayName: component.substanceDisplayName,
          route: component.administrationRouteUnwrapped.rawValue,
          units: component.unitsUnwrapped,
          dose: WatchDose(
            amount: component.doseUnwrapped,
            isEstimate: component.isEstimate,
            standardDeviation: component.estimatedDoseStandardDeviationUnwrapped))
      }))
  }

  // The watch is always dark, so it gets the dark variant
  private static func watchColor(_ color: SubstanceColor) -> WatchColor {
    let resolved = UIColor(color.swiftUIColor).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: nil)
    return WatchColor(red: red, green: green, blue: blue)
  }

  // MARK: - Logging

  private static func existingObject<Object: NSManagedObject>(uri: String, in context: NSManagedObjectContext) -> Object? {
    guard
      let url = URL(string: uri),
      let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
      let object = try? context.existingObject(with: objectID) as? Object,
      !object.isDeleted
    else { return nil }
    return object
  }

  private static func companion(for substanceName: String, in context: NSManagedObjectContext) -> SubstanceCompanion {
    let companions = PersistenceController.shared.getSubstanceCompanions()
    if let companion = companions.first(where: { $0.substanceNameUnwrapped == substanceName }) {
      return companion
    }
    let companion = SubstanceCompanion(context: context)
    companion.substanceName = substanceName
    companion.colorAsText = SubstanceColor.suggested(avoiding: companions.map(\.color)).rawValue
    return companion
  }
}

// The first ingestion ID is the watch request ID, including for formulations. A durable undo record
// blocks retries before deletion starts. Pending records are retried if the phone stops before saving.
@MainActor
final class WatchUndoJournal {
  private struct Record: Codable {
    let identifiers: [UUID]
    var isPending = true
  }

  init(file: URL) {
    self.file = file
  }

  func contains(_ id: UUID) throws -> Bool {
    try load()[id] != nil
  }

  func pending() throws -> [[UUID]] {
    try load().values.filter(\.isPending).map(\.identifiers)
  }

  func undo(_ identifiers: [UUID], delete: @escaping @MainActor ([UUID]) async throws -> Void) async throws {
    guard let id = identifiers.first else { throw WatchQuickLogError.invalidUndo }
    if let task = inProgress[id] {
      return try await task.value
    }

    var records = try load()
    let record = records[id] ?? Record(identifiers: identifiers)
    guard record.isPending else { return }
    if records[id] == nil {
      records[id] = record
      try save(records)
    }

    let task = Task {
      try await delete(record.identifiers)
      var updated = try load()
      updated[id]?.isPending = false
      try save(updated)
    }
    inProgress[id] = task
    defer { inProgress.removeValue(forKey: id) }
    try await task.value
  }

  private let file: URL
  private var records: [UUID: Record]?
  private var inProgress: [UUID: Task<Void, Error>] = [:]

  private func load() throws -> [UUID: Record] {
    if let records { return records }
    let loaded: [UUID: Record]
    do {
      loaded = try JSONDecoder().decode([UUID: Record].self, from: Data(contentsOf: file))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      loaded = [:]
    }
    records = loaded
    return loaded
  }

  private func save(_ records: [UUID: Record]) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(records).write(to: file, options: .atomic)
    self.records = records
  }
}
