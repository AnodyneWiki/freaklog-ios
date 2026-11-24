import Foundation

enum AssistantWebSearch {
  static let toolName = "search_web"

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: PersistenceController.isAssistantWebAccessEnabledKey)
  }

  @MainActor
  static func tool(limits: AssistantToolbox.Limits) -> AssistantToolbox.Tool {
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
        let key = AssistantKeychain.webSearchKey
        guard !key.isEmpty else {
          return AssistantToolbox.error("Add a Brave Search API key in Assistant settings to search the web.")
        }
        let url = try requestURL(query: arguments.string("query"))
        let json = try await AssistantHTTP.getJSON(from: url, headers: ["X-Subscription-Token": key])
        return AssistantToolbox.success(["results": .array(try results(from: json, textLimit: limits.maxTextCharacters))])
      })
  }

  static func requestURL(query: String) throws -> URL {
    guard !query.isEmpty, query.count <= 600, query.split(whereSeparator: \.isWhitespace).count <= 75 else {
      throw AssistantError("Use a nonempty web search query of up to 600 characters and 75 words.")
    }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.search.brave.com"
    components.path = "/res/v1/llm/context"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "maximum_number_of_urls", value: String(maximumResults)),
      URLQueryItem(name: "maximum_number_of_tokens", value: "2048"),
      URLQueryItem(name: "maximum_number_of_tokens_per_url", value: "512"),
    ]
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    guard let url = components.url else { throw AssistantError("Couldn’t build the web search request.") }
    return url
  }

  static func results(from json: JSONValue, textLimit: Int) throws -> [JSONValue] {
    guard let pages = json["grounding"]?["generic"]?.array else {
      throw AssistantError("Brave Search returned an unexpected response.")
    }
    return Array(pages.lazy.compactMap { page -> JSONValue? in
      guard let address = page["url"]?.string, let url = URL(string: address),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host,
            url.user == nil, url.password == nil else { return nil }
      let snippets = (page["snippets"]?.array ?? []).compactMap(\.string).joined(separator: "\n")
      guard !snippets.isEmpty else { return nil }
      return .object([
        "url": .string(url.absoluteString),
        "title": AssistantFormat.text(page["title"]?.string ?? host, limit: 160),
        "excerpt": AssistantFormat.text(snippets, limit: textLimit),
      ])
    }.prefix(maximumResults))
  }

  private static let maximumResults = 4
}
