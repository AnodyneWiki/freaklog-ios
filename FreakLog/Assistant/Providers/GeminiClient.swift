import Foundation

// Google's Gemini API. Answers come as parts; function calls and thoughts can carry thought signatures, so the
// parts are kept and sent back unchanged.
struct GeminiClient: AssistantChatClient {
  struct ReplyBuilder {
    // Adds one chunk and returns the text it adds to the answer; thoughts aren't part of it
    mutating func add(_ chunk: JSONValue) throws -> [String] {
      if let message = AssistantHTTP.errorMessage(in: chunk) {
        throw AssistantError(message)
      }
      if let reason = chunk["promptFeedback"]?["blockReason"]?.string, !reason.isEmpty {
        throw AssistantError("Gemini blocked the request (\(reason)).")
      }
      guard let candidate = chunk["candidates"]?.array?.first else { return [] }
      if let reason = candidate["finishReason"]?.string, !reason.isEmpty {
        finishReason = reason
      }
      var texts: [String] = []
      for part in candidate["content"]?["parts"]?.array ?? [] {
        parts.append(part)
        if part["thought"]?.bool != true, let text = part["text"]?.string, !text.isEmpty {
          texts.append(text)
        }
      }
      return texts
    }

    func finish() throws -> AssistantReply {
      switch finishReason {
      case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII":
        throw AssistantError("Gemini blocked the answer (\(finishReason ?? "")).", discardsPartialText: true)
      case "MALFORMED_FUNCTION_CALL":
        throw AssistantError("Gemini wrote a tool call it couldn't finish. Try asking again.")
      default:
        break
      }
      let text = parts.filter { $0["thought"]?.bool != true }.compactMap { $0["text"]?.string }.joined()
      let toolCalls = parts.compactMap { part -> AssistantToolCall? in
        guard let call = part["functionCall"], let name = call["name"]?.string else { return nil }
        let arguments = call["args"]?.object
        return AssistantToolCall(
          id: call["id"]?.string,
          name: name,
          arguments: arguments ?? [:],
          hasInvalidArguments: arguments == nil && call["args"] != nil && call["args"] != .null)
      }
      return AssistantReply(
        text: text,
        toolCalls: toolCalls,
        native: AssistantReply.Native(standard: .gemini, content: .array(parts)))
    }

    private var parts: [JSONValue] = []
    private var finishReason: String?

  }

  let endpoint: AssistantEndpoint

  // Gemini's schemas name their types in capitals (STRING, OBJECT, …)
  static func upperCasingTypes(in schema: JSONValue) -> JSONValue {
    switch schema {
    case .object(let object):
      .object(object.reduce(into: [:]) { result, entry in
        result[entry.key] = if entry.key == "type", let type = entry.value.string {
          .string(type.uppercased())
        } else {
          upperCasingTypes(in: entry.value)
        }
      })
    case .array(let array):
      .array(array.map(upperCasingTypes))
    default:
      schema
    }
  }

  func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let model = request.model.hasPrefix("models/") ? String(request.model.dropFirst(7)) : request.model
          let url = try AssistantHTTP.url(endpoint.baseURL, "models/\(model):streamGenerateContent?alt=sse")
          var reply = ReplyBuilder()
          for try await event in AssistantHTTP.events(from: url, headers: headers, body: body(for: request)) {
            for text in try reply.add(AssistantHTTP.json(of: event)) {
              continuation.yield(.text(text))
            }
          }
          try continuation.yield(.completed(reply.finish()))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func models() async throws -> [String] {
    let json = try await AssistantHTTP.getJSON(
      from: AssistantHTTP.url(endpoint.baseURL, "models?pageSize=1000"),
      headers: headers)
    return (json["models"]?.array ?? [])
      .filter { model in
        guard let methods = model["supportedGenerationMethods"]?.array else { return true }
        return methods.contains("generateContent")
      }
      .compactMap { $0["name"]?.string.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 } }
      .filter { !$0.isEmpty }
      .sorted()
  }

  func body(for request: AssistantRequest) -> JSONValue {
    var body: [String: JSONValue] = [
      "system_instruction": .object(["parts": .array([.object(["text": .string(request.system)])])]),
      "contents": .array(request.messages.map(Self.content)),
    ]
    if !request.tools.isEmpty {
      body["tools"] = .array([.object([
        "functionDeclarations": .array(request.tools.map { tool in
          .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "parameters": Self.upperCasingTypes(in: tool.parameters),
          ])
        }),
      ])])
    }
    if let maxOutputTokens = request.maxOutputTokens {
      body["generationConfig"] = .object(["maxOutputTokens": .number(Double(maxOutputTokens))])
    }
    return .object(body)
  }

  private var headers: [String: String] {
    endpoint.apiKey.isEmpty ? [:] : ["x-goog-api-key": endpoint.apiKey]
  }

  private static func content(for message: AssistantMessage) -> JSONValue {
    switch message {
    case .user(let text):
      return .object(["role": "user", "parts": .array([.object(["text": .string(text)])])])
    case .assistant(let reply):
      let parts: [JSONValue] = if let native = reply.native, native.standard == .gemini, let parts = native.content.array {
        parts
      } else {
        (reply.text.isEmpty ? [] : [.object(["text": .string(reply.text)])]) + reply.toolCalls.map { call in
          var functionCall: [String: JSONValue] = ["name": .string(call.name), "args": .object(call.arguments)]
          if let id = call.id {
            functionCall["id"] = .string(id)
          }
          return .object(["functionCall": .object(functionCall)])
        }
      }
      return .object(["role": "model", "parts": .array(parts)])
    case .toolResults(let results):
      return .object([
        "role": "user",
        "parts": .array(results.map { result in
          var response: [String: JSONValue] = ["name": .string(result.name), "response": result.result]
          if let id = result.callID {
            response["id"] = .string(id)
          }
          return .object(["functionResponse": .object(response)])
        }),
      ])
    }
  }

}
