import Foundation

// Anthropic's Messages API, also offered by some self-hosted servers. Answers come as content blocks; thinking
// blocks carry signatures, so the blocks are kept and sent back unchanged.
struct AnthropicMessagesClient: AssistantChatClient {
  // Rebuilds the message's content blocks from the stream events
  struct MessageBuilder {
    // Adds one event and returns the text it adds to the answer
    mutating func add(_ data: JSONValue, named name: String?) throws -> [String] {
      let index = try data.streamIndex(default: 0)
      switch data["type"]?.string ?? name {
      case "error":
        throw AssistantError(AssistantHTTP.errorMessage(in: data) ?? "The provider reported an error.")
      case "message":
        // A server that didn't stream sends the whole message
        var texts: [String] = []
        for (blockIndex, block) in (data["content"]?.array ?? []).enumerated() {
          blocks[blockIndex] = block.object ?? [:]
          if block["type"]?.string == "text", let text = block["text"]?.string {
            texts.append(text)
          }
        }
        setStop(data["stop_reason"], details: data["stop_details"])
        return texts
      case "content_block_start":
        let block = data["content_block"]?.object ?? [:]
        blocks[index] = block
        switch block["type"]?.string {
        case "text":
          let text = block["text"]?.string ?? ""
          texts[index] = text
          return text.isEmpty ? [] : [text]
        case "thinking":
          thinkings[index] = block["thinking"]?.string ?? ""
        case "tool_use":
          inputs[index] = ""
        default:
          break
        }
      case "content_block_delta":
        let delta = data["delta"]
        switch delta?["type"]?.string {
        case "text_delta":
          let text = delta?["text"]?.string ?? ""
          texts[index, default: ""] += text
          return text.isEmpty ? [] : [text]
        case "input_json_delta":
          inputs[index, default: ""] += delta?["partial_json"]?.string ?? ""
        case "thinking_delta":
          thinkings[index, default: ""] += delta?["thinking"]?.string ?? ""
        case "signature_delta":
          blocks[index, default: [:]]["signature"] = delta?["signature"]
        default:
          break
        }
      case "message_delta":
        setStop(data["delta"]?["stop_reason"], details: data["delta"]?["stop_details"])
      default:
        break
      }
      return []
    }

    func finish() throws -> AssistantReply {
      if stopReason == "refusal" {
        let category = stopDetails?["category"]?.string.map { " (\($0))" } ?? ""
        throw AssistantError("The model declined to answer this request\(category).", discardsPartialText: true)
      }
      var content: [JSONValue] = []
      var toolCalls: [AssistantToolCall] = []
      for (index, var block) in blocks.sorted(by: { $0.key < $1.key }) {
        if let text = texts[index] {
          block["text"] = .string(text)
        }
        if let thinking = thinkings[index] {
          block["thinking"] = .string(thinking)
        }
        if block["type"]?.string == "tool_use" {
          var arguments = block["input"]?.object
          if let input = inputs[index] {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            arguments = trimmed.isEmpty ? [:] : JSONValue(jsonText: trimmed)?.object
          }
          block["input"] = .object(arguments ?? [:])
          toolCalls.append(AssistantToolCall(
            id: block["id"]?.string,
            name: block["name"]?.string ?? "",
            arguments: arguments ?? [:],
            hasInvalidArguments: arguments == nil))
        }
        content.append(.object(block))
      }
      if stopReason == "max_tokens", !toolCalls.isEmpty {
        throw AssistantError("The answer was cut off at the output limit. Raise Max Output Tokens in the provider's settings.")
      }
      let text = content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }.joined()
      return AssistantReply(
        text: text,
        toolCalls: toolCalls,
        native: AssistantReply.Native(standard: .anthropicMessages, content: .array(content)))
    }

    private var blocks: [Int: [String: JSONValue]] = [:]
    private var texts: [Int: String] = [:]
    private var thinkings: [Int: String] = [:]
    private var inputs: [Int: String] = [:]
    private var stopReason: String?
    private var stopDetails: JSONValue?

    private mutating func setStop(_ reason: JSONValue?, details: JSONValue?) {
      if let reason = reason?.string, !reason.isEmpty {
        stopReason = reason
      }
      if let details, details != .null {
        stopDetails = details
      }
    }

  }

  static let defaultMaxOutputTokens = 64000

  let endpoint: AssistantEndpoint

  // When another model took over a declined answer, only the text before the last `fallback` block is sent back
  // with it; the declined model's thinking and tool calls aren't
  static func echoedBlocks(_ blocks: [JSONValue]) -> [JSONValue] {
    let boundary = blocks.lastIndex { $0["type"]?.string == "fallback" }
    return blocks.enumerated().compactMap { index, block in
      let type = block["type"]?.string ?? ""
      if let boundary, index <= boundary {
        return type == "text" ? block : nil
      }
      return echoedTypes.contains(type) ? block : nil
    }
  }

  func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let url = try AssistantHTTP.url(endpoint.baseURL, "messages")
          var message = MessageBuilder()
          let events = AssistantHTTP.events(
            from: url,
            headers: headers(fallbacks: usesFallbacks(request.model)),
            body: body(for: request))
          for try await event in events {
            for text in try message.add(AssistantHTTP.json(of: event), named: event.name) {
              continuation.yield(.text(text))
            }
          }
          try continuation.yield(.completed(message.finish()))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func models() async throws -> [String] {
    let url = try AssistantHTTP.url(endpoint.baseURL, "models?limit=1000")
    let json = try await AssistantHTTP.getJSON(from: url, headers: headers(fallbacks: false))
    // The API lists the newest models first, which is kept
    return (json["data"]?.array ?? []).compactMap { $0["id"]?.string }
  }

  func body(for request: AssistantRequest) -> JSONValue {
    var body: [String: JSONValue] = [
      "model": .string(request.model),
      "max_tokens": .number(Double(request.maxOutputTokens ?? Self.defaultMaxOutputTokens)),
      "stream": .bool(true),
      "system": .string(request.system),
      "messages": .array(request.messages.map(Self.message)),
    ]
    if !request.tools.isEmpty {
      body["tools"] = .array(request.tools.map { tool in
        var json: [String: JSONValue] = [
          "name": .string(tool.name),
          "description": .string(tool.description),
          "input_schema": tool.parameters,
        ]
        // Streams the arguments as they are written; MessageBuilder checks that they arrived complete
        if isOfficial {
          json["eager_input_streaming"] = .bool(true)
        }
        return .object(json)
      })
    }
    if isOfficial {
      // The tools, instructions and earlier turns are the same on every request of a chat
      body["cache_control"] = .object(["type": "ephemeral"])
    }
    if usesFallbacks(request.model) {
      // A request the model declines is answered by the model the API picks for the kind of refusal
      body["fallbacks"] = "default"
    }
    return .object(body)
  }

  private static let officialHost = "api.anthropic.com"
  private static let officialAPIVersion = "2026-10-21"
  // What other servers that speak the API understand
  private static let compatibleAPIVersion = "2023-06-01"
  private static let fallbackBeta = "server-side-fallback-2026-07-01"
  // Models whose declined requests the API can hand on to another model (`fallbacks: "default"`)
  private static let fallbackModels: Set = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]
  // The block types that are sent back; others are left out of the history
  private static let echoedTypes: Set = ["text", "thinking", "redacted_thinking", "tool_use"]

  private var isOfficial: Bool {
    URL(string: endpoint.baseURL.trimmingCharacters(in: .whitespaces))?.host == Self.officialHost
  }

  private static func message(for message: AssistantMessage) -> JSONValue {
    switch message {
    case .user(let text):
      return .object(["role": "user", "content": .array([textBlock(text)])])
    case .assistant(let reply):
      let content: [JSONValue] = if
        let native = reply.native, native.standard == .anthropicMessages,
        let blocks = native.content.array
      {
        echoedBlocks(blocks)
      } else {
        (reply.text.isEmpty ? [] : [textBlock(reply.text)]) + reply.toolCalls.map { call in
          .object([
            "type": "tool_use",
            "id": .string(call.id ?? ""),
            "name": .string(call.name),
            "input": .object(call.arguments),
          ])
        }
      }
      return .object(["role": "assistant", "content": .array(content)])
    case .toolResults(let results):
      return .object([
        "role": "user",
        "content": .array(results.map { result in
          .object([
            "type": "tool_result",
            "tool_use_id": .string(result.callID ?? ""),
            "content": .string(result.result.jsonText),
            "is_error": .bool(result.isError),
          ])
        }),
      ])
    }
  }

  private static func textBlock(_ text: String) -> JSONValue {
    .object(["type": "text", "text": .string(text)])
  }

  private func usesFallbacks(_ model: String) -> Bool {
    isOfficial && Self.fallbackModels.contains(model)
  }

  private func headers(fallbacks: Bool) -> [String: String] {
    var headers = ["anthropic-version": isOfficial ? Self.officialAPIVersion : Self.compatibleAPIVersion]
    if !endpoint.apiKey.isEmpty {
      headers["x-api-key"] = endpoint.apiKey
    }
    if fallbacks {
      headers["anthropic-beta"] = Self.fallbackBeta
    }
    return headers
  }

}
