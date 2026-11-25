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
        guard isEnabled else { return AssistantToolbox.error("Web access is turned off in Assistant settings.") }
        let query = arguments.string("query")
        guard !query.isEmpty, query.count <= 600 else {
          return AssistantToolbox.error("Use a nonempty web search query of up to 600 characters.")
        }

        let events = AssistantHTTP.events(from: endpoint, headers: [:], body: requestBody(query: query))
        for try await event in events {
          let reply = try AssistantHTTP.json(of: event)
          if reply["id"]?.number == 1 {
            return try result(from: reply, textLimit: textLimit)
          }
        }
        throw AssistantError("The web search ended without a result.")
      })
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
