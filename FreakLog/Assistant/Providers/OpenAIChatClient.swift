import Foundation

// The Chat Completions API of OpenAI, which most other providers and self-hosted servers (Ollama, LM Studio,
// vLLM, llama.cpp, LiteLLM, OpenRouter, Mistral, Groq, DeepSeek) also speak
struct OpenAIChatClient: AssistantChatClient {
  // Collects the text and the tool calls, whose names and arguments arrive in fragments
  struct ReplyBuilder {
    // Adds one chunk and returns its new text
    mutating func add(_ chunk: JSONValue) throws -> String? {
      // LiteLLM and others send `"error": null` in successful chunks
      if let message = AssistantHTTP.errorMessage(in: chunk) {
        throw AssistantError(message)
      }
      guard let choice = chunk["choices"]?.array?.first else { return nil }
      if let reason = choice["finish_reason"]?.string {
        finishReason = reason
      }
      // A server that doesn't stream answers with the whole `message` instead of `delta`s
      guard let delta = choice["delta"] ?? choice["message"] else { return nil }
      for (position, fragment) in (delta["tool_calls"]?.array ?? []).enumerated() {
        let index = fragment["index"]?.number.map(Int.init) ?? position
        var call = calls[index] ?? PendingCall()
        if let id = fragment["id"]?.string, !id.isEmpty {
          call.id = id
        }
        if let name = fragment["function"]?["name"]?.string {
          call.name += name
        }
        switch fragment["function"]?["arguments"] {
        case .string(let arguments): call.arguments += arguments
        case .object(let arguments): call.arguments = JSONValue.object(arguments).jsonText
        default: break
        }
        calls[index] = call
      }
      guard let content = delta["content"]?.string, !content.isEmpty else { return nil }
      text += content
      return content
    }

    func finish() throws -> AssistantReply {
      let toolCalls = calls.sorted { $0.key < $1.key }.map { _, call in
        let trimmed = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = trimmed.isEmpty ? [:] : JSONValue(jsonText: trimmed)?.object
        return AssistantToolCall(
          id: call.id ?? "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))",
          name: call.name,
          arguments: arguments ?? [:],
          hasInvalidArguments: arguments == nil)
      }
      if finishReason == "content_filter", text.isEmpty, toolCalls.isEmpty {
        throw AssistantError("The provider's content filter blocked the answer.")
      }
      return AssistantReply(text: text, toolCalls: toolCalls)
    }

    private struct PendingCall {
      var id: String?
      var name = ""
      var arguments = ""
    }

    private var text = ""
    private var calls: [Int: PendingCall] = [:]
    private var finishReason: String?

  }

  let endpoint: AssistantEndpoint

  func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let url = try AssistantHTTP.url(endpoint.baseURL, "chat/completions")
          var reply = ReplyBuilder()
          for try await event in AssistantHTTP.events(from: url, headers: headers, body: body(for: request, url: url)) {
            guard event.data != "[DONE]" else { break }
            if let text = try reply.add(AssistantHTTP.json(of: event)) {
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
    let json = try await AssistantHTTP.getJSON(from: AssistantHTTP.url(endpoint.baseURL, "models"), headers: headers)
    // OpenAI lists `data[].id`; some servers list `models[].name`
    let entries = json["data"]?.array ?? json["models"]?.array ?? []
    return entries.compactMap { $0["id"]?.string ?? $0["name"]?.string }.filter { !$0.isEmpty }.sorted()
  }

  func body(for request: AssistantRequest, url: URL) -> JSONValue {
    var body: [String: JSONValue] = [
      "model": .string(request.model),
      "stream": .bool(true),
      "messages": .array([.object(["role": "system", "content": .string(request.system)])]
        + request.messages.flatMap(Self.messages)),
    ]
    if !request.tools.isEmpty {
      body["tools"] = .array(request.tools.map { tool in
        .object([
          "type": "function",
          "function": .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "parameters": tool.parameters,
          ]),
        ])
      })
    }
    if let maxOutputTokens = request.maxOutputTokens {
      // OpenAI's reasoning models only take the newer name, other servers mostly only know the older one
      let key = url.host == "api.openai.com" ? "max_completion_tokens" : "max_tokens"
      body[key] = .number(Double(maxOutputTokens))
    }
    return .object(body)
  }

  // Local servers need no key, so the header is only sent with one
  private var headers: [String: String] {
    endpoint.apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(endpoint.apiKey)"]
  }

  private static func messages(for message: AssistantMessage) -> [JSONValue] {
    switch message {
    case .user(let text):
      return [.object(["role": "user", "content": .string(text)])]
    case .assistant(let reply):
      var json: [String: JSONValue] = ["role": "assistant"]
      json["content"] = reply.text.isEmpty && !reply.toolCalls.isEmpty ? .null : .string(reply.text)
      if !reply.toolCalls.isEmpty {
        json["tool_calls"] = .array(reply.toolCalls.map { call in
          .object([
            "id": .string(call.id ?? ""),
            "type": "function",
            "function": .object([
              "name": .string(call.name),
              "arguments": .string(JSONValue.object(call.arguments).jsonText),
            ]),
          ])
        })
      }
      return [.object(json)]
    case .toolResults(let results):
      return results.map { result in
        .object([
          "role": "tool",
          "tool_call_id": .string(result.callID ?? ""),
          "content": .string(result.result.jsonText),
        ])
      }
    }
  }

}
