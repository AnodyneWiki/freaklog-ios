import Foundation

enum AssistantWikipedia {
  enum Mode: String {
    case search
    case summary
  }

  @MainActor
  static func tool(textLimit: Int) -> AssistantToolbox.Tool {
    AssistantToolbox.Tool(
      name: "lookup_wikipedia",
      description: "Search Wikipedia or read an article summary with its source link.",
      parameters: [
        .init(name: "query", description: "A public topic or exact article title. Omit private details.", kind: .string, isRequired: true),
        .init(name: "mode", description: "Use summary for a known article title or search to find titles. Default: search.", kind: .string),
        .init(name: "language", description: "Wikipedia edition code such as en or de. Default: en.", kind: .string),
      ],
      progress: "Looking up Wikipedia…",
      run: { arguments in
        guard AssistantWebSearch.isEnabled else {
          throw AssistantError("Web access is turned off in Assistant settings.")
        }
        let query = arguments.string("query")
        guard !query.isEmpty, query.count <= 200 else {
          throw AssistantError("Enter a Wikipedia topic or title of up to 200 characters.")
        }
        let requestedMode = arguments.string("mode").lowercased()
        guard let mode = requestedMode.isEmpty ? .search : Mode(rawValue: requestedMode) else {
          throw AssistantError("Choose search or summary for the Wikipedia lookup.")
        }
        let edition = arguments.string("language").lowercased()
        let language = edition.isEmpty ? "en" : edition
        guard language.count <= 20, language.range(of: "^[a-z]+(-[a-z0-9]+)*$", options: .regularExpression) != nil else {
          throw AssistantError("Use a Wikipedia edition code such as en or de.")
        }
        let reply = try await AssistantHTTP.mcpToolReply(
          from: endpoint, request: requestBody(query: query, mode: mode, language: language))
        return try result(from: reply, mode: mode, language: language, textLimit: textLimit)
      })
  }

  static func requestBody(query: String, mode: Mode, language: String) -> JSONValue {
    switch mode {
    case .search:
      AssistantHTTP.mcpToolRequest(
        "wikipedia_search_articles", arguments: ["query": .string(query), "language": .string(language), "limit": .number(3)])
    case .summary:
      AssistantHTTP.mcpToolRequest(
        "wikipedia_get_summary", arguments: ["title": .string(query), "language": .string(language)])
    }
  }

  @MainActor
  static func result(from reply: JSONValue, mode: Mode, language: String, textLimit: Int) throws -> JSONValue {
    if let error = AssistantHTTP.errorMessage(in: reply) {
      throw AssistantError(error)
    }
    let result = reply["result"]
    if result?["isError"]?.bool == true {
      let detail = result?["content"]?.array?.first?["text"]?.string
      throw AssistantError(detail.map { String($0.prefix(textLimit)) } ?? "The Wikipedia lookup failed.")
    }
    guard let data = result?["structuredContent"] else {
      throw AssistantError("The Wikipedia server returned an unexpected response.")
    }
    switch mode {
    case .search:
      guard let matches = data["results"]?.array else {
        throw AssistantError("The Wikipedia server returned an unexpected search response.")
      }
      let articles = matches.prefix(3).compactMap { match -> JSONValue? in
        guard let title = match["title"]?.string, let url = articleURL(title: title, language: language) else { return nil }
        let snippet = match["snippet"]?.string ?? match["description"]?.string ?? ""
        return .object(["title": .string(title), "url": .string(url), "snippet": AssistantFormat.text(snippet, limit: 240)])
      }
      return AssistantToolbox.success(["results": .array(articles)])
    case .summary:
      guard let title = data["title"]?.string, let url = articleURL(title: title, language: language),
            let extract = data["extract"]?.string else {
        throw AssistantError("Wikipedia returned no article summary. Search for the article title.")
      }
      return AssistantToolbox.success([
        "title": .string(title),
        "url": .string(url),
        "summary": AssistantFormat.text(extract, limit: textLimit),
        "page_type": data["page_type"] ?? .null,
      ])
    }
  }

  private static func articleURL(title: String, language: String) -> String? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "\(language).wikipedia.org"
    components.path = "/wiki/" + title.replacingOccurrences(of: " ", with: "_")
    return components.url?.absoluteString
  }

  private static let endpoint = URL(string: "https://wikipedia.caseyjhand.com/mcp")!
}
