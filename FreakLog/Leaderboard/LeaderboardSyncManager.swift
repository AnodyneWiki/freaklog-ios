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

  private init() {}

  func syncAll() async {
    guard !syncing else { return }
    syncing = true
    defer { syncing = false }
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

  func notifyDeletion(identifier: UUID) async {
    let servers = LeaderboardServerStore.shared.servers.filter { $0.isActive }
    guard !servers.isEmpty else { return }
    for server in servers {
      let deviceId = DeviceIdDeriver.deviceId(for: server.host)
      let rawId = identifier.hashValue
      let ingestionId = Int32(bitPattern: UInt32(truncatingIfNeeded: rawId))
      let payload = LeaderboardEntryPayload(
        Id: deviceId,
        Nickname: server.nickname,
        Ingestion: LeaderboardIngestionPayload(
          Id: ingestionId,
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
      _ = await client.submitDelete(baseURL: server.endpoint, entry: payload)
    }
  }

  private func fetchIngestions(from start: Date, to end: Date) -> [Ingestion] {
    let request = Ingestion.fetchRequest()
    request.predicate = NSPredicate(
      format: "time >= %@ AND time < %@ AND (consumerName == nil OR consumerName == '')",
      start as NSDate,
      end as NSDate
    )
    request.sortDescriptors = [NSSortDescriptor(key: "time", ascending: true)]
    return (try? PersistenceController.shared.viewContext.fetch(request)) ?? []
  }

  private func entryPayload(ingestion: Ingestion, deviceId: String, nickname: String) -> LeaderboardEntryPayload {
    let rawId = (ingestion.identifier ?? UUID()).hashValue
    let ingestionId = Int32(bitPattern: UInt32(truncatingIfNeeded: rawId))
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
