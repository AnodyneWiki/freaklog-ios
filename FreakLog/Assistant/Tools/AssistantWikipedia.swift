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
      description: "Look up established facts in Wikipedia. Returns short article extracts and source links.",
      parameters: [
        .init(name: "query", description: "A public topic or exact article title. Omit private details.", kind: .string, isRequired: true),
        .init(name: "mode", description: "Use summary for a known title or search for up to three matching extracts. Default: search.", kind: .string),
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
        let url = try requestURL(query: query, mode: mode, language: language, textLimit: textLimit)
        let response = try await AssistantHTTP.getJSON(from: url, headers: [
          "User-Agent": "\(appName)/\(getCurrentAppVersion()) (\(repoUrl))",
        ], isLookup: true)
        return try result(from: response, mode: mode, language: language, textLimit: textLimit)
      })
  }

  static func requestURL(query: String, mode: Mode, language: String, textLimit: Int) throws -> URL {
    guard language.count <= 20, language.range(of: "^[a-z]+(-[a-z0-9]+)*$", options: .regularExpression) != nil else {
      throw AssistantError("Use a Wikipedia edition code such as en or de.")
    }
    let limit = mode == .summary ? 1 : maximumResults
    let extractLimit = mode == .summary ? min(textLimit, 1200) : min(textLimit, 240)
    var parameters = [
      "action": "query",
      "format": "json",
      "formatversion": "2",
      "prop": "extracts|pageprops",
      "ppprop": "disambiguation",
      "exintro": "1",
      "explaintext": "1",
      "exchars": String(extractLimit),
      "exlimit": String(limit),
    ]
    switch mode {
    case .search:
      // A search generator returns the lead extract for each match in the same request.
      parameters["generator"] = "search"
      parameters["gsrsearch"] = query
      parameters["gsrnamespace"] = "0"
      parameters["gsrlimit"] = String(limit)
    case .summary:
      guard !query.contains("|") else { throw AssistantError("Look up one Wikipedia article title at a time.") }
      parameters["titles"] = query
      parameters["redirects"] = "1"
    }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "\(language).wikipedia.org"
    components.path = "/w/api.php"
    components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    guard let url = components.url else { throw AssistantError("Couldn’t build the Wikipedia request.") }
    return url
  }

  @MainActor
  static func result(from response: JSONValue, mode: Mode, language: String, textLimit: Int) throws -> JSONValue {
    if let error = response["error"] {
      throw AssistantError(error["info"]?.string ?? "The Wikipedia lookup failed.")
    }
    let pages = response["query"]?["pages"]?.array
    guard pages != nil || response["batchcomplete"]?.bool == true else {
      throw AssistantError("Wikipedia returned an unexpected response.")
    }
    let rankedPages = (pages ?? []).sorted {
      ($0["index"]?.number ?? 0) < ($1["index"]?.number ?? 0)
    }
    let articles = rankedPages.prefix(maximumResults).compactMap { page -> JSONValue? in
      guard page["missing"]?.bool != true, page["invalid"]?.bool != true, let title = page["title"]?.string,
            let url = articleURL(title: title, language: language) else { return nil }
      let disambiguation = page["pageprops"]?["disambiguation"] != nil
      let extract = page["extract"]?.string ?? ""
      let text = mode == .summary ? "summary" : "snippet"
      let limit = mode == .summary ? textLimit : min(240, textLimit)
      return .object([
        "title": .string(title),
        "url": .string(url),
        text: AssistantFormat.text(extract, limit: limit),
        "page_type": disambiguation ? "disambiguation" : "standard",
      ])
    }
    if mode == .search {
      return AssistantToolbox.success(["results": .array(articles)])
    }
    guard let article = articles.first?.object, let summary = article["summary"]?.string, !summary.isEmpty else {
      throw AssistantError("Wikipedia returned no article summary. Search for the article title.")
    }
    return AssistantToolbox.success(article)
  }

  private static func articleURL(title: String, language: String) -> String? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "\(language).wikipedia.org"
    components.path = "/wiki/" + title.replacingOccurrences(of: " ", with: "_")
    return components.url?.absoluteString
  }

  private static let maximumResults = 3
}
