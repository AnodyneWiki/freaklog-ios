import Foundation

// The chat calls one local tool. Only its search query goes into the provider's separate, web-enabled request.
struct AssistantWebSearch {
  enum Provider: Equatable {
    case openAI
    case anthropic
    case openRouter

    var searchPath: String {
      switch self {
      case .openAI: "responses"
      case .anthropic: "messages"
      case .openRouter: "chat/completions"
      }
    }
  }

  static let toolName = "search_web"

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: PersistenceController.isAssistantWebAccessEnabledKey)
  }

  init?(profile: AssistantProfile, apiKey: String) {
    guard let server = try? AssistantHTTP.url(profile.baseURL, "") else { return nil }
    switch (server.host?.lowercased(), profile.standard) {
    case ("api.openai.com", .openAIChat): provider = .openAI
    case ("api.anthropic.com", .anthropicMessages): provider = .anthropic
    case ("openrouter.ai", .openAIChat): provider = .openRouter
    default: return nil
    }
    guard let url = try? AssistantHTTP.url(profile.baseURL, provider.searchPath) else { return nil }
    self.url = url
    self.apiKey = apiKey
  }

  let provider: Provider
  let url: URL
  private let apiKey: String

  @MainActor
  func tool(textLimit: Int, currentModel: @escaping @MainActor () -> String) -> AssistantToolbox.Tool {
    AssistantToolbox.Tool(
      name: Self.toolName,
      description: "Search the public web for up-to-date information. Returns a summary and source links.",
      parameters: [
        .init(
          name: "query",
          description: "A short public search query. Omit personal details and private journal content.",
          kind: .string,
          isRequired: true),
      ],
      progress: "Searching the web…",
      run: { arguments in
        guard Self.isEnabled else { return AssistantToolbox.error("Web access is turned off in Assistant settings.") }
        let query = arguments.string("query")
        guard !query.isEmpty, query.count <= 600 else {
          return AssistantToolbox.error("Use a nonempty web search query of up to 600 characters.")
        }
        return try await search(query: query, model: currentModel(), textLimit: textLimit)
      })
  }

  func requestBody(query: String, model: String) -> JSONValue {
    let prompt = "Search the public web for this query and return a concise summary with citations.\n\n" + query
    let userMessage: JSONValue = .object(["role": "user", "content": .string(prompt)])
    switch provider {
    case .openAI:
      return .object([
        "model": .string(model),
        "input": .string(prompt),
        "store": .bool(false),
        "tools": .array([.object(["type": "web_search"])]),
        "tool_choice": "required",
        "max_tool_calls": .number(3),
      ])
    case .anthropic:
      return .object([
        "model": .string(model),
        "messages": .array([userMessage]),
        "max_tokens": .number(2048),
        "tools": .array([.object(["type": "web_search_20250305", "name": "web_search", "max_uses": .number(3)])]),
      ])
    case .openRouter:
      return .object([
        "model": .string(model),
        "messages": .array([userMessage]),
        "tools": .array([.object(["type": "openrouter:web_search"])]),
      ])
    }
  }

  @MainActor
  private func search(query: String, model: String, textLimit: Int) async throws -> JSONValue {
    var body = requestBody(query: query, model: model)
    let headers = switch provider {
    case .openAI, .openRouter: ["Authorization": "Bearer \(apiKey)"]
    case .anthropic: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }
    for _ in 0 ..< 3 {
      try Task.checkCancellation()
      guard Self.isEnabled else { return AssistantToolbox.error("Web access is turned off in Assistant settings.") }
      let response = try await AssistantHTTP.postJSON(to: url, headers: headers, body: body)
      if let error = AssistantHTTP.errorMessage(in: response) {
        throw AssistantError(error)
      }
      if provider == .anthropic, response["stop_reason"]?.string == "pause_turn",
         let content = response["content"]?.array, !content.isEmpty, var fields = body.object
      {
        let messages = fields["messages"]?.array ?? []
        fields["messages"] = .array(messages + [.object(["role": "assistant", "content": .array(content)])])
        body = .object(fields)
        continue
      }
      return try result(from: response, textLimit: textLimit)
    }
    throw AssistantError("The provider paused the web search too many times. Try a more specific query.")
  }

  @MainActor
  func result(from response: JSONValue, textLimit: Int) throws -> JSONValue {
    let text: String
    let citations: [JSONValue]
    switch provider {
    case .openAI:
      let messages = (response["output"]?.array ?? []).filter { $0["type"]?.string == "message" }
      let parts = messages.flatMap { $0["content"]?.array ?? [] }.filter { $0["type"]?.string == "output_text" }
      text = parts.compactMap { $0["text"]?.string }.joined(separator: "\n")
      citations = parts.flatMap { $0["annotations"]?.array ?? [] }
    case .anthropic:
      let blocks = response["content"]?.array ?? []
      let texts = blocks.filter { $0["type"]?.string == "text" }
      text = texts.compactMap { $0["text"]?.string }.joined(separator: "\n")
      citations = texts.flatMap { $0["citations"]?.array ?? [] }
      if citations.isEmpty, let error = blocks.compactMap({ $0["content"]?["error_code"]?.string }).first {
        throw AssistantError("Anthropic web search failed (\(error)).")
      }
    case .openRouter:
      let message = response["choices"]?.array?.first?["message"]
      text = message?["content"]?.string ?? ""
      citations = (message?["annotations"]?.array ?? []).compactMap { $0["url_citation"] }
    }
    var seen: Set<URL> = []
    let sources: [JSONValue] = citations.compactMap { citation in
      guard let address = citation["url"]?.string, let url = URL(string: address),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host,
            url.user == nil, url.password == nil, seen.insert(url).inserted else { return nil }
      return .object([
        "url": .string(url.absoluteString),
        "title": AssistantFormat.text(citation["title"]?.string ?? host, limit: 160),
      ])
    }
    guard !text.isEmpty, !sources.isEmpty else {
      throw AssistantError("The provider returned no cited web results. Check that the selected model supports web search.")
    }
    return AssistantToolbox.success([
      "summary": AssistantFormat.text(text, limit: textLimit * 2),
      "sources": .array(Array(sources.prefix(8))),
    ])
  }
}
