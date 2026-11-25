import CoreData
import Foundation

// MARK: - AssistantToolbox

// The tools the model may call: journal lookups, substance data, AnodyneWiki, web search and Wikipedia. Each
// tool describes itself for the model and the chat transcript, and returns a JSON object that goes back to the
// model. Results never contain more than the question needs, because everything in them is sent to the provider.
@MainActor
final class AssistantToolbox {
  init(
    context: NSManagedObjectContext,
    limits: Limits = .standard,
    includesAnodyneWiki: Bool,
    includesWebAccess: Bool = false)
  {
    self.context = context
    self.limits = limits
    tools = journalTools() + substanceTools() + (includesAnodyneWiki ? anodyneTools() : [])
    if includesWebAccess {
      tools += [
        AssistantWebSearch.tool(textLimit: limits.maxTextCharacters),
        AssistantWikipedia.tool(textLimit: limits.maxTextCharacters),
      ]
    }
  }

  struct Tool {
    let name: String
    let description: String
    let parameters: [Parameter]
    // What the transcript shows while the tool runs, e.g. "Looking through your journal…"
    let progress: String
    let run: @MainActor ([String: JSONValue]) async throws -> JSONValue
  }

  struct Parameter {
    enum Kind {
      case string
      case integer
      case stringArray
    }

    let name: String
    let description: String
    let kind: Kind
    var isRequired = false
  }

  // How much a result may hold. Apple's on-device model has a small context window, so it gets less.
  struct Limits {
    static let standard = Limits(
      defaultListLength: 10,
      maxListLength: 50,
      defaultNotesCharacters: 2000,
      maxNotesCharacters: 8000,
      maxIngestions: 100,
      maxTextCharacters: 800)
    static let compact = Limits(
      defaultListLength: 5,
      maxListLength: 10,
      defaultNotesCharacters: 500,
      maxNotesCharacters: 1500,
      maxIngestions: 25,
      maxTextCharacters: 300)

    let defaultListLength: Int
    let maxListLength: Int
    let defaultNotesCharacters: Int
    let maxNotesCharacters: Int
    let maxIngestions: Int
    let maxTextCharacters: Int

  }

  let context: NSManagedObjectContext
  let limits: Limits
  private(set) var tools: [Tool] = []

  var specs: [AssistantToolSpec] {
    tools.map { AssistantToolSpec(name: $0.name, description: $0.description, parameters: Self.schema(of: $0.parameters)) }
  }

  static func schema(of parameters: [Parameter]) -> JSONValue {
    var properties: [String: JSONValue] = [:]
    for parameter in parameters {
      var property: [String: JSONValue] = ["description": .string(parameter.description)]
      switch parameter.kind {
      case .string: property["type"] = "string"
      case .integer: property["type"] = "integer"
      case .stringArray:
        property["type"] = "array"
        property["items"] = .object(["type": "string"])
      }
      properties[parameter.name] = .object(property)
    }
    return .object([
      "type": "object",
      "properties": .object(properties),
      "required": .array(parameters.filter(\.isRequired).map { .string($0.name) }),
    ])
  }

  static func error(_ message: String) -> JSONValue {
    .object(["status": "error", "message": .string(message)])
  }

  static func success(_ fields: [String: JSONValue]) -> JSONValue {
    .object(fields.merging(["status": "success"]) { $1 })
  }

  func tool(named name: String) -> Tool? {
    tools.first { $0.name == name }
  }

  func progress(for call: AssistantToolCall) -> String {
    tool(named: call.name)?.progress ?? "Working…"
  }

  func run(_ call: AssistantToolCall) async -> JSONValue {
    guard let tool = tool(named: call.name) else {
      return Self.error("There is no tool called '\(call.name)'.")
    }
    guard !call.hasInvalidArguments else {
      return Self.error("The arguments weren't a complete JSON object. Call the tool again with valid arguments.")
    }
    do {
      return try await tool.run(call.arguments)
    } catch is CancellationError {
      return Self.error("Stopped.")
    } catch {
      return Self.error("The tool failed: \(error.localizedDescription)")
    }
  }

  func reference(for experience: Experience) -> String {
    if let reference = experienceReferences[experience.objectID] {
      return reference
    }
    let reference = "e\(experienceReferences.count + 1)"
    experienceReferences[experience.objectID] = reference
    experienceIDs[reference] = experience.objectID
    return reference
  }

  func experience(for reference: String) -> Experience? {
    guard let id = experienceIDs[reference.trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }
    return try? context.existingObject(with: id) as? Experience
  }

  // Experiences are named to the model by short references that are only valid in this chat
  private var experienceIDs: [String: NSManagedObjectID] = [:]
  private var experienceReferences: [NSManagedObjectID: String] = [:]

}

// Reading arguments, which models send in varying forms (numbers as text, single strings for lists)
extension [String: JSONValue] {
  func string(_ key: String) -> String {
    switch self[key] {
    case .string(let string): string.trimmingCharacters(in: .whitespacesAndNewlines)
    case .number(let number): number.formatted(.number.grouping(.never))
    default: ""
    }
  }

  func integer(_ key: String, default defaultValue: Int, in range: ClosedRange<Int>) -> Int {
    let value: Int? = switch self[key] {
    case .number(let number) where number.isFinite:
      Int(exactly: Swift.min(Swift.max(number, Double(range.lowerBound)), Double(range.upperBound)).rounded(.towardZero))
    case .string(let string): Int(string.trimmingCharacters(in: .whitespaces))
    default: nil
    }
    return Swift.min(Swift.max(value ?? defaultValue, range.lowerBound), range.upperBound)
  }

  func strings(_ key: String) -> [String] {
    switch self[key] {
    case .array(let array): array.compactMap(\.string).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    case .string(let string): string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    default: []
    }
  }
}

// MARK: - AssistantFormat

// How dates and values are written in results and instructions: the local time with its weekday, so the model
// can talk about "last Saturday" without converting time zones
enum AssistantFormat {
  static func date(_ date: Date) -> String {
    formatter.string(from: date)
  }

  static func number(_ value: Double?) -> JSONValue {
    guard let value, value.isFinite else { return .null }
    return .number((value * 1000).rounded() / 1000)
  }

  static func text(_ text: String, limit: Int) -> JSONValue {
    .string(text.count > limit ? String(text.prefix(limit)) + "…" : text)
  }

  static func optionalText(_ text: String?, limit: Int) -> JSONValue {
    guard let text, !text.isEmpty else { return .null }
    return Self.text(text, limit: limit)
  }

  static func strings(_ strings: [String]) -> JSONValue {
    .array(strings.map { .string($0) })
  }

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE yyyy-MM-dd HH:mm"
    return formatter
  }()

}
