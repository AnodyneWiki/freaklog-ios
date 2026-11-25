import CoreData
import CryptoKit
import UIKit

// MARK: - WatchQuickLogError

enum WatchQuickLogError: LocalizedError {
  case customUnitMissing
  case invalidRequest
  case invalidUndo
  case conflictingRequest

  var errorDescription: String? {
    switch self {
    case .customUnitMissing:
      "This unit was deleted on your iPhone"
    case .invalidRequest:
      "The watch log request couldn't be read"
    case .invalidUndo:
      "The watch undo request couldn't be matched to a quick log"
    case .conflictingRequest:
      "This watch request ID already belongs to another quick log"
    }
  }
}

// MARK: - WatchQuickLogging

// The journal side of the watch app: the quick log suggestions it shows, and logging what it sends
// the way the add ingestion screens do, with the default experience, color, webhooks and live activity.
// Formulations never logged yet come last, as they have no recent use to sort by.
@MainActor
enum WatchQuickLogging {
  private static let legacyUndos = WatchUndoJournal(file: URL.applicationSupportDirectory.appendingPathComponent("WatchUndos.json"))

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

  static func log(_ request: WatchLogRequest) throws -> WatchAcknowledgement.Status {
    let persistence = PersistenceController.shared
    let result = try saveLog(request, in: persistence, legacyUndos: legacyUndos)
    guard !result.newIngestionIDs.isEmpty else { return result.status }

    let context = persistence.viewContext
    let ingestions = result.newIngestionIDs.compactMap { try? context.existingObject(with: $0) as? Ingestion }
    IngestionSaving.didSave(ingestions, newIngestions: ingestions, sendingWebhooksTo: WebhookPreset.defaultPresetObjectIDs())

    let wantsLiveActivity = UserDefaults.standard
      .object(forKey: PersistenceController.shouldAutomaticallyStartLiveActivityKey) as? Bool ?? true
    if
      #available(iOS 16.2, *), let experienceID = result.createdExperienceID,
      let experience = try? context.existingObject(with: experienceID) as? Experience,
      wantsLiveActivity, LiveActivities.areAvailable, !ActivityManager.shared.isActivityActive, experience.isCurrent
    {
      Task {
        await ActivityManager.shared.show(experience)
      }
    }
    return result.status
  }

  static func undo(_ request: WatchUndoRequest) throws {
    let identifiers = try saveUndo(request, in: .shared)
    if !identifiers.isEmpty {
      IngestionDeletion.didDelete(identifiers: identifiers)
    }
  }

  // Only the old journal's pending records can authorize direct deletion of an unreceipted log.
  // They were written before deletion, so a retry after a crash may have no rows left to remove.
  static func retryPendingUndos() {
    do {
      for identifiers in try legacyUndos.pending() {
        guard let request = WatchUndoRequest(legacyIdentifiers: identifiers.map(\.uuidString)) else { continue }
        do {
          let deleted = try saveUndo(request, in: .shared, recoveringLegacyUndo: true)
          if !deleted.isEmpty {
            IngestionDeletion.didDelete(identifiers: deleted)
          }
        } catch {
          print("Retrying legacy watch undo failed: \(error)")
        }
      }
    } catch {
      print("Could not read pending watch undos: \(error)")
    }
  }

  struct SaveResult {
    let status: WatchAcknowledgement.Status
    var newIngestionIDs: [NSManagedObjectID] = []
    var createdExperienceID: NSManagedObjectID?
  }

  // The receipt and all formulation components commit in the same SQLite transaction.
  static func saveLog(
    _ request: WatchLogRequest,
    in persistence: PersistenceController,
    legacyUndos: WatchUndoJournal? = nil
  ) throws -> SaveResult {
    let parts = try validatedParts(for: request)
    let identifiers = request.ingestionIdentifiers
    let fingerprint = Data(SHA256.hash(data: try WatchQuickLog.encode(request)))
    let context = try persistence.journalEditContext()
    if let (_, receipt) = try findReceipt(request.id, in: context) {
      guard receipt.identifiers == identifiers, receipt.fingerprint == nil || receipt.fingerprint == fingerprint else {
        throw WatchQuickLogError.conflictingRequest
      }
      return SaveResult(status: receipt.isUndone ? .undone : .saved)
    }
    if try legacyUndos?.contains(request.id) == true {
      return SaveResult(status: .undone)
    }

    let existing = try context.fetch(PersistenceController.ingestionsRequest(withIdentifiers: identifiers))
    if !existing.isEmpty {
      // Requests queued by an older watch can already have been saved by an older phone.
      // Adopt the rows only when the complete log still matches, without claiming they created its experience.
      guard existing.count == identifiers.count else { throw WatchQuickLogError.conflictingRequest }
      let byID = Dictionary(grouping: existing, by: \.identifier)
      for (identifier, part) in zip(identifiers, parts) {
        guard let rows = byID[identifier], rows.count == 1, let row = rows.first,
              row.time == request.time, row.substanceName == part.substanceName,
              row.administrationRoute == part.route, row.units == part.units,
              row.dose == (part.dose.amount ?? 0), row.isEstimate == part.dose.isEstimate,
              row.estimatedDoseStandardDeviation == (part.dose.standardDeviation ?? 0) else {
          throw WatchQuickLogError.conflictingRequest
        }
      }
      try insertReceipt(
        for: request.id,
        record: Receipt(identifiers: identifiers, fingerprint: fingerprint, ingestionURIs: existing.map(objectURI)),
        in: context)
      try PersistenceController.saveJournalChanges(in: context)
      return SaveResult(status: .saved)
    }

    let suggestion = request.suggestion
    var customUnit: CustomUnit?
    if let unitID = suggestion.customUnit?.id {
      guard let unit: CustomUnit = existingObject(uri: unitID, in: context) else { throw WatchQuickLogError.customUnitMissing }
      customUnit = unit
    }
    // Keep logging the snapshot if the formulation was deleted after the watch received it.
    let formulation: Formulation? = suggestion.formulation == nil ? nil : existingObject(uri: suggestion.id, in: context)
    let closestExperience = ExperienceLogic.closestExperience(
      from: try context.fetch(PersistenceController.experiencesRequest(near: request.time)),
      to: request.time)
    let experience = closestExperience ?? Experience.create(at: request.time, in: context)
    var companions = try context.fetch(PersistenceController.substanceCompanionsRequest())
    let ingestions = zip(identifiers, parts).map { identifier, part in
      let companion = companion(for: part.substanceName, in: context, companions: &companions)
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
    try context.obtainPermanentIDs(for: Array(context.insertedObjects))
    let createdExperience = closestExperience == nil ? CreatedExperience(experience) : nil
    try insertReceipt(
      for: request.id,
      record: Receipt(
        identifiers: identifiers,
        fingerprint: fingerprint,
        ingestionURIs: ingestions.map(objectURI),
        createdExperience: createdExperience),
      in: context)
    try PersistenceController.saveJournalChanges(in: context)
    return SaveResult(
      status: .saved,
      newIngestionIDs: ingestions.map(\.objectID),
      createdExperienceID: createdExperience == nil ? nil : experience.objectID)
  }

  static func saveUndo(
    _ request: WatchUndoRequest,
    in persistence: PersistenceController,
    recoveringLegacyUndo: Bool = false
  ) throws -> [UUID] {
    guard request.hasValidIdentifiers else { throw WatchQuickLogError.invalidUndo }
    let context = try persistence.journalEditContext()
    let saved = try findReceipt(request.id, in: context)
    if let (_, record) = saved {
      guard record.identifiers == request.ingestionIdentifiers else { throw WatchQuickLogError.invalidUndo }
      guard !record.isUndone else { return [] }
    }
    let matches = try context.fetch(PersistenceController.ingestionsRequest(withIdentifiers: request.ingestionIdentifiers))
    let ingestions: [Ingestion]
    if let (_, record) = saved {
      let uris = Set(record.ingestionURIs)
      ingestions = matches.filter { uris.contains(objectURI($0)) }
    } else {
      guard matches.isEmpty || recoveringLegacyUndo else { throw WatchQuickLogError.invalidUndo }
      ingestions = matches
    }

    if let (receipt, record) = saved {
      var updated = record
      updated.isUndone = true
      receipt.record = try WatchQuickLog.encode(updated)
    } else {
      // An undo can reach the phone before the original log. Record it even with no rows to delete.
      try insertReceipt(for: request.id, record: Receipt(identifiers: request.ingestionIdentifiers, isUndone: true), in: context)
    }

    let identifiers = ingestions.compactMap(\.identifier)
    try PersistenceController.withJournalStoreWrite {
      WebhookManager.stageMessageDeletion(for: ingestions, in: context)
      if let snapshot = saved?.1.createdExperience,
         let experience = ingestions.first?.experience,
         snapshot.matches(experience),
         Set(experience.ingestionsSorted) == Set(ingestions),
         ingestions.allSatisfy({ $0.location == nil }),
         experience.timedNotesSorted.isEmpty, experience.ratingsUnwrapped.isEmpty,
         persistence.viewContext.registeredObject(for: experience.objectID)?.hasChanges != true
      {
        context.delete(experience)
      } else {
        ingestions.forEach(context.delete)
      }
      try PersistenceController.saveJournalChanges(in: context)
    }
    return identifiers
  }

  private struct Receipt: Codable {
    let identifiers: [UUID]
    var fingerprint: Data?
    var ingestionURIs: [URL] = []
    var createdExperience: CreatedExperience?
    var isUndone = false
  }

  private struct CreatedExperience: Codable {
    let uri: URL
    let creationDate: Date?
    let sortDate: Date?
    let title: String?
    let text: String?
    let isFavorite: Bool

    init(_ experience: Experience) {
      uri = experience.objectID.uriRepresentation()
      creationDate = experience.creationDate
      sortDate = experience.sortDate
      title = experience.title
      text = experience.text
      isFavorite = experience.isFavorite
    }

    func matches(_ experience: Experience) -> Bool {
      uri == experience.objectID.uriRepresentation()
        && creationDate == experience.creationDate
        && sortDate == experience.sortDate
        && title == experience.title
        && text == experience.text
        && isFavorite == experience.isFavorite
        && experience.legacyLocation == nil
    }
  }

  private static func objectURI(_ object: NSManagedObject) -> URL {
    object.objectID.uriRepresentation()
  }

  private static func findReceipt(
    _ id: UUID,
    in context: NSManagedObjectContext
  ) throws -> (WatchLogReceipt, Receipt)? {
    let fetch = WatchLogReceipt.fetchRequest()
    fetch.predicate = NSPredicate(format: "requestID == %@", id as CVarArg)
    fetch.fetchLimit = 1
    guard let object = try context.fetch(fetch).first else { return nil }
    guard let data = object.record else { throw CocoaError(.fileReadCorruptFile) }
    return (object, try JSONDecoder().decode(Receipt.self, from: data))
  }

  private static func insertReceipt(for id: UUID, record: Receipt, in context: NSManagedObjectContext) throws {
    let receipt = WatchLogReceipt(context: context)
    receipt.requestID = id
    receipt.record = try WatchQuickLog.encode(record)
  }

  private typealias LogPart = (substanceName: String, route: String, units: String, dose: WatchDose)

  private static func validatedParts(for request: WatchLogRequest) throws -> [LogPart] {
    let suggestion = request.suggestion
    guard request.time.timeIntervalSinceReferenceDate.isFinite, isValid(request.dose) else {
      throw WatchQuickLogError.invalidRequest
    }

    let parts: [LogPart]
    if let formulation = suggestion.formulation {
      guard suggestion.customUnit == nil, let amount = request.dose.amount, amount > 0,
            !request.dose.isEstimate, request.dose.standardDeviation == nil,
            !formulation.components.isEmpty, formulation.components.count <= WatchQuickLog.maximumComponents,
            formulation.components.allSatisfy({ isValid($0.dose) }) else {
        throw WatchQuickLogError.invalidRequest
      }
      parts = formulation.components.map { ($0.substanceName, $0.route, $0.units, $0.dose(for: amount)) }
    } else {
      parts = [(suggestion.substanceName, suggestion.route, suggestion.units, request.dose)]
    }
    guard parts.allSatisfy({
      !$0.substanceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && AdministrationRoute(rawValue: $0.route) != nil
        && isValid($0.dose)
    }) else {
      throw WatchQuickLogError.invalidRequest
    }
    return parts
  }

  private static func isValid(_ dose: WatchDose) -> Bool {
    [dose.amount, dose.standardDeviation].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
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
    // Core Data can raise an Objective-C exception for malformed object-ID URIs.
    guard
      let url = URL(string: uri),
      url.scheme == "x-coredata", let storeID = url.host,
      let coordinator = context.persistentStoreCoordinator,
      coordinator.persistentStores.contains(where: { $0.identifier == storeID })
    else { return nil }

    let path = url.pathComponents
    let entity = String(describing: Object.self)
    guard
      path.count == 3, path[1] == entity,
      path[2].first == "p", let reference = Int64(path[2].dropFirst()), reference > 0,
      uri == "x-coredata://\(storeID)/\(entity)/p\(reference)",
      let objectID = coordinator.managedObjectID(forURIRepresentation: url),
      let object = try? context.existingObject(with: objectID) as? Object,
      !object.isDeleted
    else { return nil }
    return object
  }

  private static func companion(
    for substanceName: String,
    in context: NSManagedObjectContext,
    companions: inout [SubstanceCompanion]
  ) -> SubstanceCompanion {
    if let companion = companions.first(where: { $0.substanceNameUnwrapped == substanceName }) {
      return companion
    }
    let companion = SubstanceCompanion(context: context)
    companion.substanceName = substanceName
    companion.colorAsText = SubstanceColor.suggested(avoiding: companions.map(\.color)).rawValue
    companions.append(companion)
    return companion
  }
}

// Reads the undo tombstones written by earlier app builds.
@MainActor
struct WatchUndoJournal {
  private struct Record: Decodable {
    let identifiers: [UUID]
    let isPending: Bool
  }

  let file: URL

  func contains(_ id: UUID) throws -> Bool {
    try load()[id] != nil
  }

  func pending() throws -> [[UUID]] {
    try load().values.filter(\.isPending).map(\.identifiers)
  }

  private func load() throws -> [UUID: Record] {
    do {
      return try JSONDecoder().decode([UUID: Record].self, from: Data(contentsOf: file))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return [:]
    }
  }
}
