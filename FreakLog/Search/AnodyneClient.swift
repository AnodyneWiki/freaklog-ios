import Foundation

// Loads substances from AnodyneWiki's public JSON API (https://anodyne.wiki/api). Results, including
// substances it doesn't know, are kept on disk for a week, so a substance is only requested again after that.
// Nothing is requested unless the user asks for it or turned on automatic loading.
actor AnodyneClient {
  static let shared = AnodyneClient()

  enum Lookup: Codable, Hashable {
    case found(AnodyneSubstance)
    case notFound
  }

  private struct CachedLookup: Codable {
    let date: Date
    let lookup: Lookup
  }

  private struct CachedIndex: Codable {
    let date: Date
    let entries: [AnodyneIndexEntry]
  }

  private struct CachedUserNotes: Codable {
    let date: Date
    let notes: [AnodyneUserNote]
  }

  private static let substanceLifetime: TimeInterval = 7 * 24 * 60 * 60
  private static let indexLifetime: TimeInterval = 24 * 60 * 60
  private static let userNotesLifetime: TimeInterval = 24 * 60 * 60

  private var lookups: [String: CachedLookup] = [:]
  private var index: CachedIndex?
  private var userNotes: CachedUserNotes?

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    return URLSession(configuration: configuration)
  }()

  private init() {}

  static var isAutomaticLoadingEnabled: Bool {
    UserDefaults.standard.bool(forKey: PersistenceController.isAnodyneAutoLoadEnabledKey)
  }

  // A recent result for the name, without going online
  func cachedLookup(for name: String) -> Lookup? {
    let key = Self.key(for: name)
    if let cached = lookups[key] ?? Self.readFromDisk(CachedLookup.self, file: Self.lookupFile(for: key)),
       cached.date.distance(to: .now) < Self.substanceLifetime {
      lookups[key] = cached
      return cached.lookup
    }
    return nil
  }

  // The substance by its name, or failing that by one of the other names (e.g. common names), which are
  // looked up in AnodyneWiki's index of titles and abbreviations
  func lookup(_ name: String, otherNames: [String] = []) async throws -> Lookup {
    if let cached = cachedLookup(for: name) {
      return cached
    }
    var lookup = try await fetchSubstance(titled: name)
    if lookup == .notFound {
      let names = [name] + otherNames
      if let entry = try await indexEntries().first(where: { entry in names.contains(where: entry.matches) }),
         entry.title != name {
        lookup = try await fetchSubstance(titled: entry.title)
      }
    }
    store(lookup, for: name)
    // Pages link to each other by title, so that finds it in the cache too
    if case let .found(substance) = lookup, Self.key(for: substance.title) != Self.key(for: name) {
      store(lookup, for: substance.title)
    }
    return lookup
  }

  func indexEntries() async throws -> [AnodyneIndexEntry] {
    if let index = index ?? Self.readFromDisk(CachedIndex.self, file: Self.indexFile),
       index.date.distance(to: .now) < Self.indexLifetime {
      self.index = index
      return index.entries
    }
    let json = try await Self.fetchJSON(path: "api/index/substance")
    let entries = (json["Entries"] as? [[String: Any]] ?? []).compactMap(AnodyneIndexEntry.init(apiJSON:))
    let index = CachedIndex(date: .now, entries: entries)
    self.index = index
    Self.writeToDisk(index, file: Self.indexFile)
    return entries
  }

  // Notes from AnodyneWiki's userpages about a substance known by any of the names, without going online
  func cachedUserNotes(matching names: [String]) -> [AnodyneUserNote]? {
    guard let notes = recentUserNotes() else { return nil }
    return Self.notes(notes, matching: names)
  }

  // Userpages aren't about one substance, so loading them all doesn't tell AnodyneWiki which one is looked at
  func userNotes(matching names: [String]) async throws -> [AnodyneUserNote] {
    if let notes = recentUserNotes() {
      return Self.notes(notes, matching: names)
    }
    let users = (try await Self.fetchJSON(path: "api/index/user")["Entries"] as? [[String: Any]] ?? [])
      .compactMap { $0["Title"] as? String }
    let notes = await withTaskGroup(of: [AnodyneUserNote].self) { group in
      for user in users {
        group.addTask {
          let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
          guard let json = try? await Self.fetchJSON(path: "api/user/\(encoded)") else { return [] }
          return AnodyneUserNote.notes(fromUserJSON: json)
        }
      }
      return await group.reduce(into: []) { $0 += $1 }
    }
    let sorted = notes.sorted { $0.user.localizedCaseInsensitiveCompare($1.user) == .orderedAscending }
    let cached = CachedUserNotes(date: .now, notes: sorted)
    userNotes = cached
    AnodyneTimingStore.shared.record(sorted)
    Self.writeToDisk(cached, file: Self.userNotesFile)
    return Self.notes(cached.notes, matching: names)
  }

  private func recentUserNotes() -> [AnodyneUserNote]? {
    guard let cached = userNotes ?? Self.readFromDisk(CachedUserNotes.self, file: Self.userNotesFile),
          cached.date.distance(to: .now) < Self.userNotesLifetime
    else { return nil }
    userNotes = cached
    return cached.notes
  }

  private static func notes(_ notes: [AnodyneUserNote], matching names: [String]) -> [AnodyneUserNote] {
    let names = Set(names.map { $0.lowercased() })
    return notes.filter { names.contains($0.substanceName.lowercased()) && $0.hasDetails }
  }

  func clearCache() {
    lookups = [:]
    index = nil
    userNotes = nil
    AnodyneTimingStore.shared.clear()
    try? FileManager.default.removeItem(at: Self.directory)
  }

  func cacheSize() -> Int64 {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: Self.directory,
      includingPropertiesForKeys: [.fileSizeKey]
    )) ?? []
    return files.reduce(0) { size, file in
      size + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  // Every substance on disk with the name it was looked up by, however old, for AnodyneTimingStore
  static func cachedSubstancesOnDisk() -> [(name: String, substance: AnodyneSubstance)] {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    let prefix = lookupFile(for: "").deletingPathExtension().lastPathComponent
    return files.compactMap { file in
      let fileName = file.deletingPathExtension().lastPathComponent
      guard fileName.hasPrefix(prefix),
            let name = String(fileName.dropFirst(prefix.count)).removingPercentEncoding,
            case let .found(substance) = readFromDisk(CachedLookup.self, file: file)?.lookup
      else { return nil }
      return (name, substance)
    }
  }

  static func cachedUserNotesOnDisk() -> [AnodyneUserNote] {
    readFromDisk(CachedUserNotes.self, file: userNotesFile)?.notes ?? []
  }

  // MARK: - Network

  private func fetchSubstance(titled title: String) async throws -> Lookup {
    let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    let json = try await Self.fetchJSON(path: "api/substance/\(encoded)")
    return AnodyneSubstance(apiJSON: json).map(Lookup.found) ?? .notFound
  }

  private static func fetchJSON(path: String) async throws -> [String: Any] {
    guard let url = URL(string: "\(AnodyneSubstance.baseURL.absoluteString)/\(path)") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      throw URLError(.badServerResponse)
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw URLError(.cannotParseResponse)
    }
    return json
  }

  // MARK: - Disk cache

  private func store(_ lookup: Lookup, for name: String) {
    let key = Self.key(for: name)
    let cached = CachedLookup(date: .now, lookup: lookup)
    lookups[key] = cached
    if case let .found(substance) = lookup {
      AnodyneTimingStore.shared.record(substance, lookedUpAs: name)
    }
    Self.writeToDisk(cached, file: Self.lookupFile(for: key))
  }

  private static var directory: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AnodyneWiki", isDirectory: true)
  }

  private static var indexFile: URL {
    directory.appendingPathComponent("index.json")
  }

  private static var userNotesFile: URL {
    directory.appendingPathComponent("user-notes.json")
  }

  private static func key(for name: String) -> String {
    name.lowercased()
  }

  private static func lookupFile(for key: String) -> URL {
    let fileName = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    // The number goes up when AnodyneSubstance gains fields, so older cached substances are loaded again
    return directory.appendingPathComponent("substance3-\(fileName).json")
  }

  private static func readFromDisk<T: Decodable>(_ type: T.Type, file: URL) -> T? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func writeToDisk(_ value: some Encodable, file: URL) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
