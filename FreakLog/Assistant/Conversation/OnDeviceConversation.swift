import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - OnDeviceModel

// Apple's on-device model, for the parts of the app that run on any iOS version
enum OnDeviceModel {
  // Whether this iOS version has the model at all, even if this device can't run it
  static var isSupportedBySystem: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return true
    }
    #endif
    return false
  }

  // Why the model can't be used right now, nil when it can
  static var unavailableReason: String? {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return nil
      case .unavailable(.deviceNotEligible):
        return "This device can't run Apple's on-device model."
      case .unavailable(.appleIntelligenceNotEnabled):
        return "Turn on Apple Intelligence in the Settings app to use the on-device model."
      case .unavailable(.modelNotReady):
        return "The on-device model is still downloading. Try again later."
      case .unavailable:
        return "Apple's on-device model isn't available right now."
      }
    }
    #endif
    return "Apple's on-device model needs iOS 26."
  }

  @MainActor
  static func conversation(instructions: String, toolbox: AssistantToolbox) -> (any AssistantConversation)? {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return OnDeviceConversation(instructions: instructions, toolbox: toolbox)
    }
    #endif
    return nil
  }
}

#if canImport(FoundationModels)
// A chat with Apple's on-device model. The framework runs the tool calls itself; the tools report to the turn
// that is streaming so the transcript shows them like those of the other providers.
@available(iOS 26.0, *)
@MainActor
final class OnDeviceConversation: AssistantConversation {
  init(instructions: String, toolbox: AssistantToolbox) {
    let reporter = ToolEventReporter()
    let tools = toolbox.specs.compactMap { spec in
      (try? DynamicTool(spec: spec, toolbox: toolbox, reporter: reporter)).map { $0 as any FoundationModels.Tool }
    }
    self.reporter = reporter
    self.tools = tools
    session = LanguageModelSession(tools: tools, instructions: instructions)
  }

  func send(_ text: String) -> AsyncThrowingStream<AssistantTurnEvent, Error> {
    AsyncThrowingStream { continuation in
      let previous = runningTurn
      let task = Task { @MainActor in
        // The session takes one request at a time, also while a stopped one winds down
        await previous?.value
        reporter.continuation = continuation
        do {
          var written = ""
          for try await snapshot in session.streamResponse(to: text) {
            let content = snapshot.content
            // Snapshots hold the whole answer so far
            if content.hasPrefix(written) {
              let delta = String(content.dropFirst(written.count))
              if !delta.isEmpty {
                continuation.yield(.text(delta))
              }
            } else {
              continuation.yield(.text(String(content.dropFirst(written.commonPrefix(with: content).count))))
            }
            written = content
          }
          continuation.yield(.completed(written))
          continuation.finish()
        } catch let error as LanguageModelSession.GenerationError {
          continuation.finish(throwing: Self.assistantError(for: error))
        } catch {
          continuation.finish(throwing: error)
        }
        reporter.continuation = nil
      }
      runningTurn = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func rollBackLastTurn() -> String? {
    let entries = Array(session.transcript)
    guard
      let index = entries.lastIndex(where: { if case .prompt = $0 { true } else { false } }),
      case .prompt(let prompt) = entries[index]
    else { return nil }
    let text = prompt.segments.compactMap { segment in
      if case .text(let text) = segment { text.content } else { nil }
    }.joined()
    // The instructions are the first entry, so the new session keeps them
    session = LanguageModelSession(tools: tools, transcript: Transcript(entries: entries[..<index]))
    return text
  }

  private let tools: [any FoundationModels.Tool]
  private let reporter: ToolEventReporter
  private var session: LanguageModelSession
  private var runningTurn: Task<Void, Never>?

  private static func assistantError(for error: LanguageModelSession.GenerationError) -> AssistantError {
    switch error {
    case .exceededContextWindowSize:
      AssistantError("This chat is too long for the on-device model. Start a new chat.")
    case .guardrailViolation, .refusal:
      AssistantError("The on-device model declined to answer this.", discardsPartialText: true)
    case .unsupportedLanguageOrLocale:
      AssistantError("The on-device model doesn't support this language.")
    case .assetsUnavailable:
      AssistantError(OnDeviceModel.unavailableReason ?? "The on-device model isn't available right now.")
    case .rateLimited, .concurrentRequests:
      AssistantError("The on-device model is busy. Try again in a moment.")
    default:
      AssistantError(error.localizedDescription)
    }
  }
}

// Hands the tool events of the turn that is streaming to it
@available(iOS 26.0, *)
final class ToolEventReporter: @unchecked Sendable {
  var continuation: AsyncThrowingStream<AssistantTurnEvent, Error>.Continuation? {
    get { lock.withLock { current } }
    set { lock.withLock { current = newValue } }
  }

  func nextKey() -> String {
    lock.withLock {
      count += 1
      return "\(count)"
    }
  }

  private let lock = NSLock()
  private var current: AsyncThrowingStream<AssistantTurnEvent, Error>.Continuation?
  private var count = 0

}

// One of the toolbox's tools in the form the framework takes. The JSON Schema of its parameters becomes a
// dynamic generation schema, and the generated arguments become JSON again.
@available(iOS 26.0, *)
struct DynamicTool: FoundationModels.Tool {
  init(spec: AssistantToolSpec, toolbox: AssistantToolbox, reporter: ToolEventReporter) throws {
    name = spec.name
    description = spec.description
    self.toolbox = toolbox
    self.reporter = reporter
    let required = Set((spec.parameters["required"]?.array ?? []).compactMap(\.string))
    let properties = (spec.parameters["properties"]?.object ?? [:]).sorted { $0.key < $1.key }.map { name, property in
      DynamicGenerationSchema.Property(
        name: name,
        description: property["description"]?.string,
        schema: Self.schema(for: property),
        isOptional: !required.contains(name))
    }
    parameters = try GenerationSchema(root: DynamicGenerationSchema(name: spec.name, properties: properties), dependencies: [])
  }

  let name: String
  let description: String
  let parameters: GenerationSchema

  func call(arguments: GeneratedContent) async throws -> String {
    let call = AssistantToolCall(id: nil, name: name, arguments: Self.json(from: arguments).object ?? [:])
    let key = reporter.nextKey()
    reporter.continuation?.yield(.toolStarted(key: key, call: call))
    let result = await toolbox.run(call)
    reporter.continuation?.yield(.toolFinished(key: key, call: call, result: result))
    return result.jsonText
  }

  private let toolbox: AssistantToolbox
  private let reporter: ToolEventReporter

  private static func schema(for property: JSONValue) -> DynamicGenerationSchema {
    switch property["type"]?.string {
    case "integer": DynamicGenerationSchema(type: Int.self)
    case "array": DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
    default: DynamicGenerationSchema(type: String.self)
    }
  }

  private static func json(from content: GeneratedContent) -> JSONValue {
    switch content.kind {
    case .null: .null
    case .bool(let bool): .bool(bool)
    case .number(let number): .number(number)
    case .string(let string): .string(string)
    case .array(let array): .array(array.map(json))
    case .structure(let properties, _): .object(properties.mapValues(json))
    @unknown default: .null
    }
  }
}
#endif
