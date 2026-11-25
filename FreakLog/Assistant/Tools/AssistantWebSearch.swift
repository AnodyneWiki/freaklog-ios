import Foundation

enum AssistantWebSearch {
  static let toolName = "search_web"

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: PersistenceController.isAssistantWebAccessEnabledKey)
  }

  @MainActor
  static func tool(textLimit: Int) -> AssistantToolbox.Tool {
    AssistantToolbox.Tool(
      name: toolName,
      description: "Search the public web for up-to-date information. Returns excerpts with links to their sources.",
      parameters: [
        .init(
          name: "query",
          description: "A short public search query. Omit personal details and private journal content.",
          kind: .string,
          isRequired: true),
      ],
      progress: "Searching the web…",
      run: { arguments in
        try await search(query: arguments.string("query"), textLimit: textLimit)
      })
  }

  @MainActor
  static func search(query: String, textLimit: Int) async throws -> JSONValue {
    guard isEnabled else { throw AssistantError("Web access is turned off in Assistant settings.") }
    guard !query.isEmpty, query.count <= 600 else {
      throw AssistantError("Use a nonempty web search query of up to 600 characters.")
    }

    let events = AssistantHTTP.events(from: endpoint, headers: [:], body: requestBody(query: query), isLookup: true)
    for try await event in events {
      let reply = try AssistantHTTP.json(of: event)
      if reply["id"]?.number == 1 {
        return try result(from: reply, textLimit: textLimit)
      }
    }
    throw AssistantError("The web search ended without a result.")
  }

  struct SearchResult: Equatable {
    let title: String
    let url: URL?
    let snippet: String
  }

  static func searchResults(from result: JSONValue) -> [SearchResult] {
    let excerpts = result["results"]?.array?.compactMap(\.string) ?? []
    return excerpts.map { excerpt in
      var lines = excerpt.components(separatedBy: .newlines)
      let title = lines.first.flatMap { $0.hasPrefix("Title: ") ? String($0.dropFirst(7)) : nil }
      if title != nil { lines.removeFirst() }

      var url: URL?
      if let line = lines.first, line.hasPrefix("URL: ") {
        let address = String(line.dropFirst(5))
        if let candidate = URL(string: address),
           let scheme = candidate.scheme?.lowercased(), ["http", "https"].contains(scheme),
           candidate.host != nil, candidate.user == nil, candidate.password == nil {
          url = candidate
        }
        lines.removeFirst()
      }
      while let line = lines.first,
            line.hasPrefix("Published Date:") || line.hasPrefix("Author:") || line.isEmpty {
        lines.removeFirst()
      }
      let snippet = lines.joined(separator: "\n")
        .replacingOccurrences(of: #"^(Highlights|Text):\s*"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return SearchResult(title: title ?? url?.host ?? "Web Result", url: url, snippet: snippet)
    }
  }

  static func requestBody(query: String) -> JSONValue {
    .object([
      "jsonrpc": "2.0",
      "id": .number(1),
      "method": "tools/call",
      "params": .object([
        "name": "web_search_exa",
        "arguments": .object(["query": .string(query), "numResults": .number(3)]),
      ]),
    ])
  }

  @MainActor
  static func result(from reply: JSONValue, textLimit: Int) throws -> JSONValue {
    if let message = AssistantHTTP.errorMessage(in: reply) {
      throw AssistantError(message)
    }
    guard let result = reply["result"], let content = result["content"]?.array else {
      throw AssistantError("The web search returned an unexpected response.")
    }
    let text = content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }.joined(separator: "\n")
    if result["isError"]?.bool == true {
      throw AssistantError(text.isEmpty ? "Web search failed." : String(text.prefix(textLimit)))
    }
    let excerpts = text.components(separatedBy: "\n\n---\n\n")
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .prefix(3)
      .map { AssistantFormat.text($0, limit: textLimit) }
    return AssistantToolbox.success(["results": .array(excerpts)])
  }

  // Exa's hosted MCP search supports individual tool calls without an account or session.
  private static let endpoint = URL(string: "https://mcp.exa.ai/mcp?tools=web_search_exa")!
}
