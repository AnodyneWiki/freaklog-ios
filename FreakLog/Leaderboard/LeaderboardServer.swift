import Foundation

struct LeaderboardServer: Codable, Identifiable {
  var id: UUID
  var scheme: String
  var host: String
  var port: Int?
  var nickname: String
  var createdAt: Date
  var startsAt: Date
  var expiresAt: Date
  var isPaused: Bool
  var lastSyncAt: Date?
  var lastSyncStatus: String?

  init(
    id: UUID = UUID(),
    scheme: String = "https",
    host: String,
    port: Int? = nil,
    nickname: String,
    createdAt: Date = Date(),
    startsAt: Date = Date(),
    expiresAt: Date = Date().addingTimeInterval(7 * 24 * 3600),
    isPaused: Bool = false,
    lastSyncAt: Date? = nil,
    lastSyncStatus: String? = nil
  ) {
    self.id = id
    self.scheme = scheme
    self.host = host
    self.port = port
    self.nickname = nickname
    self.createdAt = createdAt
    self.startsAt = startsAt
    self.expiresAt = expiresAt
    self.isPaused = isPaused
    self.lastSyncAt = lastSyncAt
    self.lastSyncStatus = lastSyncStatus
  }

  var endpoint: String {
    if let port {
      return "\(scheme)://\(host):\(port)"
    }
    return "\(scheme)://\(host)"
  }

  var isExpired: Bool {
    Date() >= expiresAt
  }

  var hasStarted: Bool {
    Date() >= startsAt
  }

  var isActive: Bool {
    hasStarted && !isExpired && !isPaused
  }
}

final class LeaderboardServerStore: ObservableObject {
  static let shared = LeaderboardServerStore()

  @Published private(set) var servers: [LeaderboardServer] = []

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  // After the settings were replaced, e.g. by restoring a backup
  func reload() {
    servers = []
    load()
  }

  func add(_ server: LeaderboardServer) {
    servers.append(server)
    save()
  }

  func update(_ server: LeaderboardServer) {
    guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }
    servers[idx] = server
    save()
  }

  func delete(id: UUID) {
    servers.removeAll { $0.id == id }
    save()
  }

  func markSynced(id: UUID, status: String) {
    guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
    servers[idx].lastSyncAt = Date()
    servers[idx].lastSyncStatus = status
    save()
  }

  private func load() {
    guard let data = defaults.data(forKey: PersistenceController.leaderboardServersKey) else { return }
    if let decoded = try? JSONDecoder().decode([LeaderboardServer].self, from: data) {
      servers = decoded
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(servers) {
      defaults.set(data, forKey: PersistenceController.leaderboardServersKey)
    }
  }
}
