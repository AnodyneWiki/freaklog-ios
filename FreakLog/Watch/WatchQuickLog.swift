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
  // Message or user info: the identifiers of the ingestions a request logged, to delete them again
  static let undoKey = "undo"
  // Message asking for the current suggestions; the reply carries them under suggestionsKey
  static let refreshKey = "refresh"
  // Reply to a log or undo message that the iPhone could not save
  static let errorKey = "error"

  static func encode(_ value: some Encodable) throws -> Data {
    try JSONEncoder().encode(value)
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
