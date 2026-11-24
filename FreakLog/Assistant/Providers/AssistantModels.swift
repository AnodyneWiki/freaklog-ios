import Foundation

// MARK: - AssistantAPIStandard

// The wire protocols the assistant speaks. Self-hosted servers usually implement one of the first two.
enum AssistantAPIStandard: String, Codable, CaseIterable, Identifiable, Sendable {
  case openAIChat
  case anthropicMessages
  case gemini
  // Apple's model on the device, through the Foundation Models framework (iOS 26)
  case onDevice

  var id: Self { self }

  var name: String {
    switch self {
    case .openAIChat: "OpenAI Chat Completions"
    case .anthropicMessages: "Anthropic Messages"
    case .gemini: "Google Gemini"
    case .onDevice: "Apple on-device model"
    }
  }

  // The standards a server can speak, for the API picker
  static let serverStandards: [AssistantAPIStandard] = [.openAIChat, .anthropicMessages, .gemini]
}

// MARK: - AssistantToolCall

// A function call the model asks the app to run
struct AssistantToolCall: Hashable, Sendable {
  // The provider's id for the call. Gemini can leave it out; OpenAI and Anthropic always send one.
  let id: String?
  let name: String
  let arguments: [String: JSONValue]
  // The model sent arguments that aren't a JSON object, e.g. cut off at the output limit
  var hasInvalidArguments = false
}

// MARK: - AssistantToolResult

struct AssistantToolResult: Hashable, Sendable {
  let callID: String?
  let name: String
  let result: JSONValue

  var isError: Bool {
    result["status"]?.string == "error"
  }
}

// MARK: - AssistantReply

// One answer of the model. `native` is the provider's own form of it (Anthropic's content blocks, Gemini's
// parts), sent back as it is so signed thinking blocks and thought signatures survive the round trip.
struct AssistantReply: Hashable, Sendable {
  var text: String
  var toolCalls: [AssistantToolCall] = []
  var native: Native?

  struct Native: Hashable, Sendable {
    let standard: AssistantAPIStandard
    let content: JSONValue
  }
}

// MARK: - AssistantMessage

// The conversation history, the same for every provider
enum AssistantMessage: Hashable, Sendable {
  case user(String)
  case assistant(AssistantReply)
  case toolResults([AssistantToolResult])
}

// MARK: - AssistantToolSpec

// A tool the model may call. `parameters` is a JSON Schema object with lowercase types.
struct AssistantToolSpec: Hashable, Sendable {
  let name: String
  let description: String
  let parameters: JSONValue
}

// MARK: - AssistantRequest

struct AssistantRequest: Sendable {
  let model: String
  let system: String
  let messages: [AssistantMessage]
  let tools: [AssistantToolSpec]
  // Nil leaves the limit to the provider where it allows that
  let maxOutputTokens: Int?
}

// MARK: - AssistantStreamEvent

enum AssistantStreamEvent: Sendable {
  case text(String)
  // Always the last event of a successful stream
  case completed(AssistantReply)
}

// MARK: - AssistantEndpoint

// Where and how to reach a provider
struct AssistantEndpoint: Sendable {
  let baseURL: String
  let apiKey: String
}

// MARK: - AssistantChatClient

// One provider's implementation of a standard
protocol AssistantChatClient: Sendable {
  // Streams one answer of the model. Failures are thrown as AssistantError.
  func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>

  // The model ids the endpoint offers
  func models() async throws -> [String]
}

// MARK: - AssistantError

// A failure talking to a provider, worded for the user. `discardsPartialText` means text streamed before the
// failure must not be kept as an answer, e.g. after a refusal mid-answer.
struct AssistantError: LocalizedError, Sendable {
  let message: String
  var discardsPartialText = false

  init(_ message: String, discardsPartialText: Bool = false) {
    self.message = message
    self.discardsPartialText = discardsPartialText
  }

  var errorDescription: String? { message }
}

extension AssistantChatClient {
  // Runs a whole request and returns the answer's text, for the connection test
  func complete(_ request: AssistantRequest) async throws -> String {
    var text = ""
    for try await event in stream(request) {
      switch event {
      case .text(let delta): text += delta
      case .completed(let reply): if text.isEmpty { text = reply.text }
      }
    }
    return text
  }
}

// MARK: - JSONValue + ExpressibleByStringLiteral

extension JSONValue: ExpressibleByStringLiteral {
  init(stringLiteral value: String) {
    self = .string(value)
  }

  // Parses a JSON text, nil when it isn't valid JSON
  init?(jsonText: String) {
    guard let data = jsonText.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
      return nil
    }
    self = value
  }

  // A JSON text of the value, e.g. a tool result for providers that take tool results as strings
  var jsonText: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
  }

}
