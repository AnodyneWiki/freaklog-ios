import Foundation

// MARK: - ServerSentEvent

// One server-sent event. A server that ignored `stream: true` and answered with plain JSON arrives as a
// single event without a name.
struct ServerSentEvent: Hashable, Sendable {
  var name: String?
  var data: String
}

// MARK: - ServerSentEventParser

// Turns the lines of a server-sent event stream into events: `data:` lines are joined until an empty line
// ends the event, `event:` names it and comments (`:`) are skipped.
struct ServerSentEventParser {
  mutating func feed(_ line: String) -> ServerSentEvent? {
    if line.isEmpty {
      return finish()
    }
    if line.hasPrefix(":") {
      return nil
    }
    let field: Substring
    var value: Substring
    if let colon = line.firstIndex(of: ":") {
      field = line[..<colon]
      value = line[line.index(after: colon)...]
      if value.hasPrefix(" ") {
        value = value.dropFirst()
      }
    } else {
      field = line[...]
      value = ""
    }
    switch field {
    case "data": dataLines.append(String(value))
    case "event": name = String(value)
    default: break
    }
    return nil
  }

  // The event still open when the stream ends
  mutating func finish() -> ServerSentEvent? {
    defer {
      name = nil
      dataLines = []
    }
    guard !dataLines.isEmpty else { return nil }
    return ServerSentEvent(name: name, data: dataLines.joined(separator: "\n"))
  }

  private var name: String?
  private var dataLines: [String] = []

}

// MARK: - AssistantHTTP

// The HTTP calls of the provider clients. Cancelling the task that reads a stream cancels its request.
enum AssistantHTTP {
  static let maxEventBytes = 8 * 1024 * 1024

  // Joins a base URL and a path without doubling or dropping the slash, and only allows HTTPS, or HTTP to
  // this device itself
  static func url(_ baseURL: String, _ path: String) throws -> URL {
    let joined = baseURL.trimmingCharacters(in: .whitespaces).trimmingSuffix("/") + "/" + path.trimmingPrefix("/")
    guard let url = URL(string: joined), let scheme = url.scheme?.lowercased(), url.host != nil else {
      throw AssistantError("“\(baseURL)” isn't a valid server address.")
    }
    guard scheme == "https" || scheme == "http" else {
      throw AssistantError("Only http:// and https:// addresses are supported.")
    }
    if isInsecureRemote(url) {
      throw AssistantError("Remote servers need HTTPS. HTTP is only allowed for a server on this device (localhost).")
    }
    return url
  }

  // HTTP to another machine, which would send the journal data unencrypted
  static func isInsecureRemote(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else { return false }
    return !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
  }

  // POSTs the body and streams the answer as server-sent events
  static func events(
    from url: URL,
    headers: [String: String],
    body: JSONValue)
    -> AsyncThrowingStream<ServerSentEvent, Error>
  {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
          for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
          }
          request.httpBody = Data(body.jsonText.utf8)
          let (bytes, response) = try await connect { try await session.bytes(for: request) }
          try await checkStatus(response, bytes: bytes)
          let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
          if contentType.localizedCaseInsensitiveContains("json") {
            let data = try await collect(bytes, limit: maxEventBytes, host: url.host)
            continuation.yield(ServerSentEvent(name: nil, data: String(decoding: data, as: UTF8.self)))
          } else {
            var parser = ServerSentEventParser()
            var line: [UInt8] = []
            var eventBytes = 0
            // Lines are split by hand because `bytes.lines` drops the empty lines that end events
            for try await byte in bytes {
              eventBytes += 1
              guard eventBytes <= maxEventBytes else {
                throw AssistantError("\(url.host ?? "The server") sent an event that is too large.")
              }
              if byte == UInt8(ascii: "\n") {
                if line.last == UInt8(ascii: "\r") {
                  line.removeLast()
                }
                if line.isEmpty { eventBytes = 0 }
                if let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                  continuation.yield(event)
                }
                line.removeAll(keepingCapacity: true)
              } else {
                line.append(byte)
              }
            }
            if !line.isEmpty, let event = parser.feed(String(decoding: line, as: UTF8.self)) {
              continuation.yield(event)
            }
            if let event = parser.finish() {
              continuation.yield(event)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func getJSON(from url: URL, headers: [String: String]) async throws -> JSONValue {
    try await requestJSON(from: url, headers: headers)
  }

  static func postJSON(to url: URL, headers: [String: String], body: JSONValue) async throws -> JSONValue {
    try await requestJSON(from: url, headers: headers, body: body)
  }

  private static func requestJSON(from url: URL, headers: [String: String], body: JSONValue? = nil) async throws -> JSONValue {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    for (field, value) in headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    let (bytes, response) = try await connect { try await session.bytes(for: request) }
    try await checkStatus(response, bytes: bytes)
    let data = try await collect(bytes, limit: maxEventBytes, host: url.host)
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
      throw AssistantError("\(url.host ?? "The server") answered with something that isn't JSON.")
    }
    return json
  }

  // Decodes the data of an event, which every provider sends as JSON
  static func json(of event: ServerSentEvent) throws -> JSONValue {
    guard let json = JSONValue(jsonText: event.data) else {
      throw AssistantError("The server sent an answer that isn't JSON.")
    }
    return json
  }

  // The message of an error object, which all providers put under `error.message`
  static func errorMessage(in json: JSONValue?) -> String? {
    guard let error = json?["error"] else { return nil }
    if let message = error["message"]?.string ?? error.string, !message.isEmpty {
      return message
    }
    return error == .null ? nil : error.jsonText
  }

  private static let maxErrorCharacters = 600

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    // Local models can take minutes before the first token
    configuration.timeoutIntervalForRequest = 300
    configuration.timeoutIntervalForResource = 60 * 60
    return URLSession(configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
  }()

  // Credentials and journal content belong to the configured origin, including on redirects.
  static func sameOrigin(_ first: URL?, _ second: URL?) -> Bool {
    guard let first, let second, let host = first.host, let scheme = first.scheme?.lowercased() else { return false }
    let defaultPort = scheme == "https" ? 443 : 80
    return scheme == second.scheme?.lowercased() && host.lowercased() == second.host?.lowercased()
      && (first.port ?? defaultPort) == (second.port ?? defaultPort)
  }

  private final class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void)
    {
      completionHandler(AssistantHTTP.sameOrigin(task.originalRequest?.url, request.url) ? request : nil)
    }
  }

  private static func connect<T>(_ operation: () async throws -> T) async throws -> T {
    do {
      return try await operation()
    } catch let error as URLError {
      throw AssistantError(message(for: error))
    }
  }

  private static func message(for error: URLError) -> String {
    switch error.code {
    case .cancelled: "The request was cancelled."
    case .timedOut: "The server took too long to answer."
    case .cannotFindHost, .dnsLookupFailed: "The server address couldn't be found."
    case .cannotConnectToHost: "Couldn't connect to the server. Is it running?"
    case .notConnectedToInternet, .networkConnectionLost: "There is no internet connection."
    case .appTransportSecurityRequiresSecureConnection: "This server needs an HTTPS address."
    default: error.localizedDescription
    }
  }

  private static func checkStatus(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
    guard let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) else { return }
    let host = http.url?.host ?? "The server"
    let data = (try? await collect(bytes, limit: 64 * 1024, host: host)) ?? Data()
    let body = String(decoding: data, as: UTF8.self)
    let detail = errorMessage(in: JSONValue(jsonText: body)) ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
    let explanation = switch http.statusCode {
    case 401, 403: "The API key was rejected."
    case 404: "The address or model wasn't found."
    case 429: "Too many requests, or the account's limit is reached."
    case 500...: "The server had a problem."
    default: "The request failed."
    }
    let suffix = detail.isEmpty ? "" : "\n\n" + String(detail.prefix(maxErrorCharacters))
    throw AssistantError("\(explanation) (\(host), HTTP \(http.statusCode))\(suffix)")
  }

  private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int, host: String?) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > limit {
        throw AssistantError("\(host ?? "The server") sent an answer that is too large.")
      }
    }
    return data
  }
}

extension String {
  fileprivate func trimmingSuffix(_ suffix: Character) -> String {
    var result = self
    while result.last == suffix {
      result.removeLast()
    }
    return result
  }

  fileprivate func trimmingPrefix(_ prefix: Character) -> String {
    String(drop(while: { $0 == prefix }))
  }
}
