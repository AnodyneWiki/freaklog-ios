import CryptoKit
import Foundation

// Loads substances from AnodyneWiki's public JSON API (https://anodyne.wiki/api, or the instance set in
// Settings). Results, including substances it doesn't know, are kept on disk for a week, so a substance is
// only requested again after that. Nothing is requested unless the user asks for it or turned on automatic
// loading.
actor AnodyneClient {
  static let defaultCacheRoot = URL.cachesDirectory.appendingPathComponent("AnodyneWikiByInstance", isDirectory: true)
  static let shared = AnodyneClient()

  typealias LoadData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  struct RequestContext: Equatable, Sendable {
    let baseURL: URL
    fileprivate let generation: Int
  }

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
  private static let maxConcurrentUserPages = 6

  private var lookups: [String: CachedLookup] = [:]
  private var index: CachedIndex?
  private var userNotes: CachedUserNotes?
  private var cacheInstance: URL?
  // A switch or a cache deletion invalidates requests that have already started.
  private var cacheGeneration = 0
  private let cacheRoot: URL
  private let configuredInstance: @Sendable () -> URL
  private let fallbackStore: AnodyneFallbackStore
  private let loadData: LoadData

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    return URLSession(configuration: configuration)
  }()

  init(
    cacheRoot: URL = AnodyneClient.defaultCacheRoot,
    configuredInstance: @escaping @Sendable () -> URL = { AnodyneSubstance.baseURL },
    fallbackStore: AnodyneFallbackStore = .shared,
    loadData: @escaping LoadData = { try await AnodyneClient.session.data(for: $0) }
  ) {
    self.cacheRoot = cacheRoot
    self.configuredInstance = configuredInstance
    self.fallbackStore = fallbackStore
    self.loadData = loadData
  }

  static var isAutomaticLoadingEnabled: Bool {
    UserDefaults.standard.bool(forKey: PersistenceController.isAnodyneAutoLoadEnabledKey)
  }

  func requestContext() -> RequestContext {
    let instance = configuredInstance()
    if cacheInstance != instance {
      resetMemoryCache()
      cacheInstance = instance
    }
    return RequestContext(baseURL: instance, generation: cacheGeneration)
  }

  // Both Settings and backup restore apply changes here, so they can't interleave with an old response.
  func applyInstanceChange(_ update: @Sendable () -> Void) {
    let previous = requestContext().baseURL
    update()
    if requestContext().baseURL != previous {
      fallbackStore.clearCache(for: previous)
    }
  }

  func isCurrent(_ context: RequestContext) -> Bool {
    context == requestContext() && !Task.isCancelled
  }

  private func requireCurrent(_ context: RequestContext) throws {
    guard isCurrent(context) else { throw CancellationError() }
  }

  // A recent result for the name, without going online
  func cachedLookup(for name: String, using context: RequestContext? = nil) -> Lookup? {
    let context = context ?? requestContext()
    guard isCurrent(context) else { return nil }
    let key = Self.key(for: name)
    let files = AnodyneCacheFiles(root: cacheRoot, instance: context.baseURL)
    if let cached = lookups[key] ?? Self.readFromDisk(CachedLookup.self, file: files.lookupFile(for: key)),
       cached.date.distance(to: .now) < Self.substanceLifetime {
      lookups[key] = cached
      return cached.lookup
    }
    return nil
  }

  // The substance by its name, or failing that by one of the other names (e.g. common names), which are
  // looked up in AnodyneWiki's index of titles and abbreviations
  func lookup(_ name: String, otherNames: [String] = [], using context: RequestContext? = nil) async throws -> Lookup {
    let context = context ?? requestContext()
    try requireCurrent(context)
    let cached = cachedLookup(for: name, using: context)
    if let cached, cached != .notFound || otherNames.isEmpty {
      return cached
    }

    var lookup: Lookup
    if let cached {
      lookup = cached
    } else {
      lookup = try await fetchSubstance(titled: name, from: context.baseURL)
    }
    try requireCurrent(context)
    if lookup == .notFound {
      let names = [name] + otherNames
      let entries = try await indexEntries(using: context)
      if let entry = entries.first(where: {
        $0.title != name && names.contains(where: $0.matches)
      }) {
        if Self.key(for: entry.title) != Self.key(for: name),
           let cachedAlias = cachedLookup(for: entry.title, using: context) {
          lookup = cachedAlias
        } else {
          try requireCurrent(context)
          lookup = try await fetchSubstance(titled: entry.title, from: context.baseURL)
          try requireCurrent(context)
          if lookup == .notFound {
            store(lookup, for: entry.title, from: context.baseURL)
          }
        }
      }
    }
    try requireCurrent(context)
    if cached == nil || lookup != .notFound {
      store(lookup, for: name, from: context.baseURL)
    }
    // Pages link to each other by title, so that finds it in the cache too
    if case let .found(substance) = lookup, Self.key(for: substance.title) != Self.key(for: name) {
      store(lookup, for: substance.title, from: context.baseURL)
    }
    return lookup
  }

  func indexEntries(using context: RequestContext? = nil) async throws -> [AnodyneIndexEntry] {
    let context = context ?? requestContext()
    try requireCurrent(context)
    let files = AnodyneCacheFiles(root: cacheRoot, instance: context.baseURL)
    if let index = index ?? Self.readFromDisk(CachedIndex.self, file: files.index),
       index.date.distance(to: .now) < Self.indexLifetime {
      self.index = index
      return index.entries
    }
    let response = try await Self.fetchIndex("substance", from: context.baseURL, loadData: loadData)
    let entries = response.compactMap(AnodyneIndexEntry.init(apiJSON:))
    try requireCurrent(context)
    let index = CachedIndex(date: .now, entries: entries)
    self.index = index
    Self.writeToDisk(index, file: files.index)
    return entries
  }

  // Notes from AnodyneWiki's userpages about a substance known by any of the names, without going online.
  // These are the last saved notes however old, since screens offer no way to load them again.
  func cachedUserNotes(matching names: [String], using context: RequestContext? = nil) -> [AnodyneUserNote] {
    let context = context ?? requestContext()
    guard isCurrent(context) else { return [] }
    let files = AnodyneCacheFiles(root: cacheRoot, instance: context.baseURL)
    guard let cached = userNotes ?? Self.readFromDisk(CachedUserNotes.self, file: files.userNotes) else { return [] }
    userNotes = cached
    return Self.notes(cached.notes, matching: names)
  }

  // Userpages aren't about one substance, so loading them all doesn't tell AnodyneWiki which one is looked at.
  // A download where some userpages failed is never cached: those users' notes from before stand in for theirs.
  func userNotes(matching names: [String], using context: RequestContext? = nil) async throws -> [AnodyneUserNote] {
    let context = context ?? requestContext()
    try requireCurrent(context)
    let files = AnodyneCacheFiles(root: cacheRoot, instance: context.baseURL)
    if let notes = recentUserNotes(in: files) {
      return Self.notes(notes, matching: names)
    }
    let loadData = loadData
    let entries = try await Self.fetchIndex("user", from: context.baseURL, loadData: loadData)
    try requireCurrent(context)
    let users = try entries.map { entry in
      guard let title = entry["Title"] as? String, !title.isEmpty else {
        throw URLError(.cannotParseResponse)
      }
      return title
    }
    var notes: [AnodyneUserNote] = []
    var failedUsers = Set<String>()
    await withTaskGroup(of: (user: String, notes: [AnodyneUserNote]?).self) { group in
      func collect(_ result: (user: String, notes: [AnodyneUserNote]?)) {
        if let fetched = result.notes {
          notes += fetched
        } else {
          failedUsers.insert(result.user)
        }
      }
      // A sliding window, so only a few userpages are requested at a time
      for (offset, user) in users.enumerated() {
        if offset >= Self.maxConcurrentUserPages, let result = await group.next() {
          collect(result)
          guard isCurrent(context) else {
            group.cancelAll()
            return
          }
        }
        group.addTask { (user, await Self.fetchNotes(ofUser: user, from: context.baseURL, loadData: loadData)) }
      }
      for await result in group {
        collect(result)
      }
    }
    try requireCurrent(context)
    if !failedUsers.isEmpty {
      let previous = (userNotes ?? Self.readFromDisk(CachedUserNotes.self, file: files.userNotes))?.notes ?? []
      return Self.notes(Self.sorted(notes + previous.filter { failedUsers.contains($0.user) }), matching: names)
    }
    let sorted = Self.sorted(notes)
    let cached = CachedUserNotes(date: .now, notes: sorted)
    userNotes = cached
    fallbackStore.record(sorted, from: context.baseURL)
    Self.writeToDisk(cached, file: files.userNotes)
    return Self.notes(cached.notes, matching: names)
  }

  // A user's notes, nil when their userpage couldn't be loaded. A page titled differently than the index entry
  // counts as failed too, because notes are told apart by the page's title.
  private static func fetchNotes(ofUser user: String, from instance: URL, loadData: LoadData) async -> [AnodyneUserNote]? {
    let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
    guard let json = try? await fetchJSON(path: "api/user/\(encoded)", from: instance, loadData: loadData),
          json["Title"] as? String == user else {
      return nil
    }
    if let tried = json["TriedSubstances"] {
      guard let entries = tried as? [[String: Any]],
            entries.allSatisfy({ ($0["Name"] as? String)?.isEmpty == false }) else {
        return nil
      }
    }
    return AnodyneUserNote.notes(fromUserJSON: json)
  }

  private static func sorted(_ notes: [AnodyneUserNote]) -> [AnodyneUserNote] {
    notes.sorted { $0.user.localizedCaseInsensitiveCompare($1.user) == .orderedAscending }
  }

  private func recentUserNotes(in files: AnodyneCacheFiles) -> [AnodyneUserNote]? {
    guard let cached = userNotes ?? Self.readFromDisk(CachedUserNotes.self, file: files.userNotes),
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
    let instance = requestContext().baseURL
    resetMemoryCache()
    fallbackStore.clearCache(for: instance)
  }

  private func resetMemoryCache() {
    cacheGeneration += 1
    lookups = [:]
    index = nil
    userNotes = nil
  }

  func cacheSize() -> Int64 {
    let directory = AnodyneCacheFiles(root: cacheRoot, instance: requestContext().baseURL).directory
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey]
    )) ?? []
    return files.reduce(0) { size, file in
      size + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  // Every substance on disk with the name it was looked up by, however old, for AnodyneFallbackStore.
  // Files from before the current format are skipped.
  static func cachedSubstancesOnDisk(in cache: AnodyneCacheFiles) -> [(name: String, substance: AnodyneSubstance)] {
    let files = (try? FileManager.default.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)) ?? []
    return files.compactMap { file in
      let fileName = file.deletingPathExtension().lastPathComponent
      guard fileName.hasPrefix(AnodyneCacheFiles.lookupPrefix),
            let name = String(fileName.dropFirst(AnodyneCacheFiles.lookupPrefix.count)).removingPercentEncoding,
            case let .found(substance) = readFromDisk(CachedLookup.self, file: file)?.lookup
      else { return nil }
      return (name, substance)
    }
  }

  // Substances cached before the current format, which are loaded again when needed
  static func removeOutdatedFilesOnDisk(in cache: AnodyneCacheFiles) {
    let files = (try? FileManager.default.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.lastPathComponent.hasPrefix("substance")
      && !file.lastPathComponent.hasPrefix(AnodyneCacheFiles.lookupPrefix) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  static func cachedUserNotesOnDisk(in cache: AnodyneCacheFiles) -> [AnodyneUserNote] {
    readFromDisk(CachedUserNotes.self, file: cache.userNotes)?.notes ?? []
  }

  // MARK: - Network

  private static func fetchIndex(_ name: String, from instance: URL, loadData: LoadData) async throws -> [[String: Any]] {
    let json = try await fetchJSON(path: "api/index/\(name)", from: instance, loadData: loadData)
    guard let entries = json["Entries"] as? [[String: Any]] else {
      throw URLError(.cannotParseResponse)
    }
    return entries
  }

  private func fetchSubstance(titled title: String, from instance: URL) async throws -> Lookup {
    let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    let json = try await Self.fetchJSON(path: "api/substance/\(encoded)", from: instance, loadData: loadData)
    return AnodyneSubstance(apiJSON: json).map(Lookup.found) ?? .notFound
  }

  private static func fetchJSON(path: String, from instance: URL, loadData: LoadData) async throws -> [String: Any] {
    guard let url = URL(string: "\(instance.absoluteString)/\(path)") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await loadData(request)
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      throw URLError(.badServerResponse)
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw URLError(.cannotParseResponse)
    }
    return json
  }

  // MARK: - Disk cache

  private func store(_ lookup: Lookup, for name: String, from instance: URL) {
    let key = Self.key(for: name)
    let cached = CachedLookup(date: .now, lookup: lookup)
    lookups[key] = cached
    if case let .found(substance) = lookup {
      fallbackStore.record(substance, lookedUpAs: name, from: instance)
    }
    let files = AnodyneCacheFiles(root: cacheRoot, instance: instance)
    Self.writeToDisk(cached, file: files.lookupFile(for: key))
  }

  private static func key(for name: String) -> String {
    name.lowercased()
  }

  private static func readFromDisk<T: Decodable>(_ type: T.Type, file: URL) -> T? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func writeToDisk(_ value: some Encodable, file: URL) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}

struct AnodyneCacheFiles {
  // Bump when AnodyneSubstance gains fields, so older cached substances are loaded again.
  static let lookupPrefix = "substance3-"
  let directory: URL

  init(root: URL, instance: URL) {
    // Include the entire base URL, including port and path, in a filesystem-safe key.
    let key = SHA256.hash(data: Data(instance.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    directory = root.appendingPathComponent(key, isDirectory: true)
  }

  var index: URL { directory.appendingPathComponent("index.json") }
  var userNotes: URL { directory.appendingPathComponent("user-notes.json") }

  // The old cache has no record of which instance supplied its data.
  static func discardLegacyCache() {
    let legacy = URL.cachesDirectory.appendingPathComponent("AnodyneWiki", isDirectory: true)
    try? FileManager.default.removeItem(at: legacy)
  }

  func lookupFile(for key: String) -> URL {
    let fileName = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    return directory.appendingPathComponent("\(Self.lookupPrefix)\(fileName).json")
  }
}
