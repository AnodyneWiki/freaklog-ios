import CoreData
import Foundation

struct SyncLogEntry: Identifiable {
  let id = UUID()
  let date: Date
  let serverNickname: String?
  let message: String
  let isError: Bool
}

@MainActor
final class LeaderboardSyncManager: ObservableObject {
  static let shared = LeaderboardSyncManager()

  @Published var syncing = false
  @Published var log: [SyncLogEntry] = []

  private let client = LeaderboardClient.shared
  // Set when a sync is asked for while one runs, so changes saved meanwhile are sent once it finishes
  private var isSyncRequested = false

  private init() {}

  func syncAll() async {
    guard !syncing else {
      isSyncRequested = true
      return
    }
    syncing = true
    defer { syncing = false }
    repeat {
      isSyncRequested = false
      for server in LeaderboardServerStore.shared.servers {
        if server.isPaused {
          logEntry(server.nickname, "Skipped: paused")
          continue
        }
        if server.isExpired {
          logEntry(server.nickname, "Skipped: expired")
          continue
        }
        if !server.hasStarted {
          logEntry(server.nickname, "Skipped: waiting for start time")
          continue
        }
        await syncServer(server)
      }
    } while isSyncRequested
  }

  func syncServer(_ server: LeaderboardServer) async {
    let deviceId = DeviceIdDeriver.deviceId(for: server.host)
    let ingestions = fetchIngestions(from: server.startsAt, to: server.expiresAt)
    if !ingestions.isEmpty {
      let entries = ingestions.map { entryPayload(ingestion: $0, deviceId: deviceId, nickname: server.nickname) }
      let result = await client.submitBatch(baseURL: server.endpoint, entries: entries)
      switch result {
      case .success:
        LeaderboardServerStore.shared.markSynced(id: server.id, status: "success")
        logEntry(server.nickname, "Synced \(entries.count) entries")
      case .httpError(let code):
        logEntry(server.nickname, "Sync failed: HTTP \(code)", isError: true)
        return
      case .networkError(let error):
        logEntry(server.nickname, "Sync failed: \(error.localizedDescription)", isError: true)
        return
      }
    } else {
      LeaderboardServerStore.shared.markSynced(id: server.id, status: "success")
      logEntry(server.nickname, "Sync complete: no ingestions in window")
    }
  }

  func notifyDeletion(identifiers: [UUID]) async {
    let servers = LeaderboardServerStore.shared.servers.filter { $0.isActive }
    let payloads = servers.flatMap { server in
      identifiers.map { (endpoint: server.endpoint, payload: deletionPayload(identifier: $0, server: server)) }
    }
    await withTaskGroup(of: Void.self) { group in
      for (endpoint, payload) in payloads {
        group.addTask {
          _ = await LeaderboardClient.shared.submitDelete(baseURL: endpoint, entry: payload)
        }
      }
    }
  }

  private func deletionPayload(identifier: UUID, server: LeaderboardServer) -> LeaderboardEntryPayload {
    LeaderboardEntryPayload(
      Id: DeviceIdDeriver.deviceId(for: server.host),
      Nickname: server.nickname,
      Ingestion: LeaderboardIngestionPayload(
        Id: identifier.leaderboardId,
          SubstanceName: "",
          Time: 0,
          EndTime: 0,
          CreationDate: 0,
          AdministrationRoute: "",
          Dose: 0,
          IsDoseAnEstimate: 0,
          EstimatedDoseStandardDeviation: 0,
          Units: "",
          Notes: "",
        StomachFullness: "",
        Category: ""
      ),
      Normalized: nil
    )
  }

  private func fetchIngestions(from start: Date, to end: Date) -> [Ingestion] {
    PersistenceController.shared.getPersonalIngestions(from: start, to: end)
  }

  private func entryPayload(ingestion: Ingestion, deviceId: String, nickname: String) -> LeaderboardEntryPayload {
    let ingestionId = (ingestion.identifier ?? UUID()).leaderboardId
    let timeEpoch = Int64(ingestion.timeUnwrapped.timeIntervalSince1970)
    let endTimeEpoch = Int64((ingestion.endTime ?? ingestion.timeUnwrapped).timeIntervalSince1970)
    let creationEpoch = Int64((ingestion.creationDate ?? ingestion.timeUnwrapped).timeIntervalSince1970)
    let category = ingestion.substance?.categories.first ?? ""
    let ingestionPayload = LeaderboardIngestionPayload(
      Id: ingestionId,
      SubstanceName: ingestion.substanceNameUnwrapped,
      Time: timeEpoch,
      EndTime: endTimeEpoch,
      CreationDate: creationEpoch,
      AdministrationRoute: ingestion.administrationRouteUnwrapped.rawValue,
      Dose: ingestion.doseUnwrapped ?? 0.0,
      IsDoseAnEstimate: ingestion.isEstimate ? 1 : 0,
      EstimatedDoseStandardDeviation: ingestion.estimatedDoseStandardDeviation,
      Units: ingestion.unitsUnwrapped,
      Notes: ingestion.noteUnwrapped,
      StomachFullness: ingestion.stomachFullness ?? "",
      Category: category
    )
    return LeaderboardEntryPayload(
      Id: deviceId,
      Nickname: nickname,
      Ingestion: ingestionPayload,
      Normalized: nil
    )
  }

  private func logEntry(_ nickname: String?, _ message: String, isError: Bool = false) {
    let entry = SyncLogEntry(date: Date(), serverNickname: nickname, message: message, isError: isError)
    log.insert(entry, at: 0)
    if log.count > 300 {
      log = Array(log.prefix(300))
    }
  }
}

extension UUID {
  // Leaderboard entries are keyed by an Int32. Taken from the UUID's bytes so it is the same on every launch,
  // unlike hashValue, which is seeded per process and made deletions miss the submitted entry.
  var leaderboardId: Int32 {
    let bytes = uuid
    return Int32(bitPattern: UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3))
  }
}
