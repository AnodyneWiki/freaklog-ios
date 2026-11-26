import Foundation

// MARK: - WatchQuickLog

// What the iPhone app and the watch app exchange over WatchConnectivity. This file belongs to both targets.
// The iPhone owns the journal: it sends its quick log suggestions to the watch as the application context,
// and the watch asks the iPhone to log, or undo, an ingestion.
enum WatchQuickLog {
  // Application context: the encoded [WatchSuggestion]
  static let suggestionsKey = "suggestions"
  // Message or user info: an encoded WatchLogRequest
  static let logKey = "log"
  // Message or user info: an encoded WatchUndoRequest (older watches send an array of UUID strings)
  static let undoKey = "undo"
  static let routineTakenKey = "routineTaken"
  static let routineSnapshotKey = "routineSnapshot"
  static let requestIDKey = "requestID"
  static let acknowledgementKey = "acknowledgement"
  // Message asking for the current suggestions; the reply carries them under suggestionsKey
  static let refreshKey = "refresh"
  // Error reply understood by older watches
  static let errorKey = "error"

  static func encode(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }

  static func decode<T: Decodable>(_ type: T.Type, from data: Any?) -> T? {
    guard let data = data as? Data else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  // A crown step that takes about 20 turns to reach the dose, rounded to 1, 2 or 5 times a power of ten:
  // 100 mg moves by 5 mg, 250 µg by 10 µg, 1.5 g by 0.1 g
  static func doseStep(around dose: Double) -> Double {
    guard dose > 0 else { return 1 }
    let rough = dose / 20
    let magnitude = pow(10, floor(log10(rough)))
    let step = [1.0, 2, 5, 10].first { $0 * magnitude >= rough * 0.75 } ?? 10
    return step * magnitude
  }

  // The identifier of the ingestion a request logs for the component at the index of a formulation:
  // the request's own for the first, derived from it for the others, so they are all known before logging
  static func ingestionIdentifier(for requestID: UUID, component index: Int) -> UUID {
    guard index > 0 else { return requestID }
    var bytes = requestID.uuid
    bytes.15 = bytes.15 &+ UInt8(truncatingIfNeeded: index)
    bytes.14 = bytes.14 &+ UInt8(truncatingIfNeeded: index >> 8)
    return UUID(uuid: bytes)
  }

  static let maximumComponents = 65_536
}

// MARK: - WatchSuggestion

// One substance and route (and custom unit, if any) with the doses recently logged for it,
// or a formulation, whose doses are amounts of it, e.g. 2 for two pills
struct WatchSuggestion: Codable, Hashable, Identifiable {
  let id: String
  // The stored name, which the iPhone logs with
  let substanceName: String
  let displayName: String
  let route: String
  let color: WatchColor
  // Dose units, e.g. "mg"; for a custom unit the units of one unit's dose
  let units: String
  let customUnit: WatchCustomUnit?
  // Most recent first
  let doses: [WatchDose]
  var formulation: WatchFormulation? = nil

  // Where the crown starts for another dose
  var typicalDose: Double {
    doses.lazy.compactMap(\.amount).first ?? 0
  }

  var doseStep: Double {
    customUnit == nil && formulation == nil ? WatchQuickLog.doseStep(around: typicalDose) : 0.5
  }

  func description(of dose: WatchDose) -> String {
    guard let amount = dose.amount else { return "Unknown dose" }
    if formulation != nil {
      return "\(amount.asRoundedReadableString)×"
    }
    return amount.doseDescription(
      units: customUnit?.unitName(for: amount) ?? units,
      isEstimate: dose.isEstimate,
      standardDeviation: dose.standardDeviation,
      rounded: customUnit != nil)
  }

  // What a number of custom units comes to, e.g. "200 mg" for 2 pills,
  // or an amount of a formulation, e.g. "200 mg MDMA, 100 mg Caffeine"
  func calculatedDescription(of dose: WatchDose) -> String? {
    if let formulation, let amount = dose.amount {
      return formulation.components.map { component in
        "\(component.description(of: component.dose(for: amount))) \(component.displayName)"
      }.joined(separator: ", ")
    }
    guard let customUnit, let amount = dose.amount, let dosePerUnit = customUnit.dosePerUnit else { return nil }
    return (amount * dosePerUnit).doseDescription(
      units: units,
      isEstimate: dose.isEstimate || customUnit.isEstimate,
      standardDeviation: nil,
      rounded: true)
  }
}

// MARK: - WatchCustomUnit

struct WatchCustomUnit: Codable, Hashable {
  // The unit's object ID URI
  let id: String
  let name: String
  let singular: String
  let plural: String
  let dosePerUnit: Double?
  let isEstimate: Bool

  func unitName(for amount: Double) -> String {
    amount == 1 ? singular : plural
  }
}

// MARK: - WatchFormulation

struct WatchFormulation: Codable, Hashable {
  let components: [WatchFormulationComponent]
}

// MARK: - WatchFormulationComponent

struct WatchFormulationComponent: Codable, Hashable {
  // The stored name, which the iPhone logs with
  let substanceName: String
  let displayName: String
  let route: String
  let units: String
  // In one unit of the formulation
  let dose: WatchDose
  var isHiddenInTimeline: Bool?

  // The amount is exact, so the deviation scales with it
  func dose(for amount: Double) -> WatchDose {
    WatchDose(
      amount: dose.amount.map { $0 * amount },
      isEstimate: dose.isEstimate,
      standardDeviation: dose.standardDeviation.map { $0 * amount })
  }

  func description(of dose: WatchDose) -> String {
    dose.amount?.doseDescription(
      units: units,
      isEstimate: dose.isEstimate,
      standardDeviation: dose.standardDeviation,
      rounded: true) ?? "Unknown dose"
  }
}

// MARK: - WatchDose

struct WatchDose: Codable, Hashable {
  // Nil for an unknown dose; for a custom unit the number of units
  let amount: Double?
  let isEstimate: Bool
  let standardDeviation: Double?
}

// MARK: - WatchColor

struct WatchColor: Codable, Hashable {
  let red: Double
  let green: Double
  let blue: Double
}

// MARK: - WatchLogRequest

struct WatchLogRequest: Codable, Hashable, Identifiable {
  // Becomes the ingestion's identifier, so a request delivered twice is logged once
  let id: UUID
  let suggestion: WatchSuggestion
  let dose: WatchDose
  let time: Date

  // One ingestion, or one for each component of a formulation
  var ingestionIdentifiers: [UUID] {
    let count = suggestion.formulation?.components.count ?? 1
    return (0 ..< count).map { WatchQuickLog.ingestionIdentifier(for: id, component: $0) }
  }
}

struct WatchUndoRequest: Codable, Equatable, Identifiable {
  let id: UUID
  let ingestionIdentifiers: [UUID]
  private var usesLegacyPayload: Bool?

  init(log: WatchLogRequest) {
    id = log.id
    ingestionIdentifiers = log.ingestionIdentifiers
  }

  init?(legacyIdentifiers: [String]) {
    guard let id = legacyIdentifiers.first.flatMap(UUID.init(uuidString:)) else { return nil }
    let identifiers = legacyIdentifiers.compactMap(UUID.init(uuidString:))
    guard identifiers.count == legacyIdentifiers.count else { return nil }
    self.id = id
    ingestionIdentifiers = identifiers
    usesLegacyPayload = true
  }

  var legacyPayload: [String]? {
    usesLegacyPayload == true ? ingestionIdentifiers.map(\.uuidString) : nil
  }

  var hasValidIdentifiers: Bool {
    !ingestionIdentifiers.isEmpty
      && ingestionIdentifiers.count <= WatchQuickLog.maximumComponents
      && ingestionIdentifiers.enumerated().allSatisfy {
        $0.element == WatchQuickLog.ingestionIdentifier(for: id, component: $0.offset)
      }
  }
}

enum WatchRequestKind: String, Codable {
  case log
  case undo
  case routineTaken

  var messageKey: String {
    switch self {
    case .log: WatchQuickLog.logKey
    case .undo: WatchQuickLog.undoKey
    case .routineTaken: WatchQuickLog.routineTakenKey
    }
  }
}

enum WatchRequest: Codable, Equatable, Identifiable {
  case log(WatchLogRequest)
  case undo(WatchUndoRequest)
  case routineTaken(RoutineTakenRequest)

  var id: UUID {
    switch self {
    case .log(let request): request.id
    case .undo(let request): request.id
    case .routineTaken(let request): request.id
    }
  }

  var kind: WatchRequestKind {
    switch self {
    case .log: .log
    case .undo: .undo
    case .routineTaken: .routineTaken
    }
  }

  init?(kind: WatchRequestKind, payload: Any?) {
    switch kind {
    case .log:
      guard let request = WatchQuickLog.decode(WatchLogRequest.self, from: payload) else { return nil }
      self = .log(request)
    case .undo:
      let request = WatchQuickLog.decode(WatchUndoRequest.self, from: payload)
        ?? (payload as? [String]).flatMap(WatchUndoRequest.init(legacyIdentifiers:))
      guard let request else { return nil }
      self = .undo(request)
    case .routineTaken:
      guard let request = WatchQuickLog.decode(RoutineTakenRequest.self, from: payload) else { return nil }
      self = .routineTaken(request)
    }
  }

  func message() throws -> [String: Any] {
    // An undo recovered from the old WatchConnectivity queue still uses the old wire format.
    if case .undo(let request) = self, let identifiers = request.legacyPayload {
      return [kind.messageKey: identifiers, WatchQuickLog.requestIDKey: id.uuidString]
    }
    let payload = switch self {
    case .log(let request): try WatchQuickLog.encode(request)
    case .undo(let request): try WatchQuickLog.encode(request)
    case .routineTaken(let request): try WatchQuickLog.encode(request)
    }
    return [kind.messageKey: payload, WatchQuickLog.requestIDKey: id.uuidString]
  }
}

struct WatchAcknowledgement: Codable, Equatable {
  enum Status: String, Codable {
    case saved
    case undone
    case retry
    case rejected
  }

  let id: UUID
  let kind: WatchRequestKind
  let status: Status
  var message: String? = nil
}

// WatchConnectivity finishing a transfer only means it reached the phone.
// The outbox keeps it until the phone confirms the outcome of the journal transaction.
struct WatchRequestOutbox {
  struct Rejection: Codable, Identifiable {
    let request: WatchRequest
    let message: String

    var id: UUID { request.id }
  }

  private struct State: Codable {
    var pending: [UUID: WatchRequest] = [:]
    var rejections: [Rejection] = []
  }

  let file: URL
  private var state = State()

  var pending: [UUID: WatchRequest] { state.pending }
  var rejections: [Rejection] { state.rejections }

  init(file: URL) throws {
    self.file = file
    do {
      state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      // The first operation creates the file.
    }
  }

  mutating func enqueue(_ request: WatchRequest) throws {
    var updated = state
    updated.pending[request.id] = request
    updated.rejections.removeAll { $0.id == request.id }
    try save(updated)
  }

  @discardableResult
  mutating func acknowledge(_ acknowledgement: WatchAcknowledgement) throws -> Bool {
    guard let request = pending[acknowledgement.id], request.kind == acknowledgement.kind else { return false }
    var updated = state
    switch acknowledgement.status {
    case .retry:
      return false
    case .saved:
      guard request.kind != .undo else { return false }
    case .undone:
      break
    case .rejected:
      updated.rejections.append(Rejection(request: request, message: acknowledgement.message ?? "Your iPhone rejected the request"))
    }
    updated.pending[request.id] = nil
    try save(updated)
    return true
  }

  mutating func dismissRejection(_ id: UUID) throws {
    var updated = state
    updated.rejections.removeAll { $0.id == id }
    try save(updated)
  }

  private mutating func save(_ updated: State) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try WatchQuickLog.encode(updated).write(to: file, options: .atomic)
    state = updated
  }
}
