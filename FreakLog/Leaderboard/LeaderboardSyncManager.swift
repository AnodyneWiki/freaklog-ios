import CoreData
import Foundation

struct SyncLogEntry: Identifiable {
  let id = UUID()
  let date: Date
  let serverID: UUID
  let message: String
  let isError: Bool
}

@MainActor
final class LeaderboardSyncManager: ObservableObject {
  static let shared = LeaderboardSyncManager(
    client: LeaderboardClient.shared,
    serverStore: .shared,
    persistence: { .shared }
  )

  @Published private(set) var syncing = false
  @Published private(set) var log: [SyncLogEntry] = []
  @Published private(set) var pendingDeletionCount = 0
  @Published private(set) var publicationRecordError: String?
  @Published private(set) var deletionError: String?

  private struct Destination: Codable, Hashable {
    let serverID: UUID
    let endpoint: String
    let deviceID: String
  }

  private struct PublicationRecord: Codable, Equatable {
    var nickname: String
    // Also covers submissions whose response was lost after the server received them.
    var tracked: Set<UUID> = []
    var retained: Set<UUID> = []
    var pendingDeletions: Set<UUID> = []

    var isEmpty: Bool { tracked.isEmpty && retained.isEmpty && pendingDeletions.isEmpty }
  }

  private static let publicationsKey = "leaderboardPublications"
  private let client: LeaderboardSyncClient
  private let serverStore: LeaderboardServerStore
  private let persistence: () -> PersistenceController
  private let defaults: UserDefaults
  private let deviceID: (String) -> String
  private var publications: [Destination: PublicationRecord] = [:]
  private var isSyncRequested = false
  private var isDeletionRetryRequested = false
  private var journalRevision = 0

  init(
    client: LeaderboardSyncClient,
    serverStore: LeaderboardServerStore,
    persistence: @escaping () -> PersistenceController,
    defaults: UserDefaults = .standard,
    deviceID: @escaping (String) -> String = DeviceIdDeriver.deviceId(for:)
  ) {
    self.client = client
    self.serverStore = serverStore
    self.persistence = persistence
    self.defaults = defaults
    self.deviceID = deviceID

    guard let data = defaults.data(forKey: Self.publicationsKey) else { return }
    do {
      publications = try JSONDecoder().decode([Destination: PublicationRecord].self, from: data)
      updatePendingDeletionCount()
    } catch {
      publicationRecordError = "Could not read saved leaderboard publications. \(error.localizedDescription)"
    }
  }

  func syncAll() async {
    isSyncRequested = true
    await processRequests()
  }

  func queueDeletions(identifiers: [UUID]) {
    let identifiers = Set(identifiers)
    guard !identifiers.isEmpty else { return }
    var updated = publications
    for (destination, var record) in updated {
      let matching = record.tracked.union(record.retained).intersection(identifiers)
      guard !matching.isEmpty else { continue }
      record.tracked.subtract(matching)
      record.retained.subtract(matching)
      record.pendingDeletions.formUnion(matching)
      updated[destination] = record
    }
    if updated != publications {
      savePublications(updated)
    }
  }

  func retryPendingDeletions() async {
    isDeletionRetryRequested = true
    await processRequests()
  }

  func notifyDeletion(identifiers: [UUID]) async {
    queueDeletions(identifiers: identifiers)
    await retryPendingDeletions()
  }

  // Intentional journal replacement can keep remote rows. Reclaim eligible rows on the next successful
  // publication and keep the original destinations for future explicit deletions.
  func journalWasReplaced() {
    journalRevision += 1
    var updated = publications
    for (destination, var record) in updated where !record.tracked.isEmpty {
      record.retained.formUnion(record.tracked)
      record.tracked.removeAll()
      updated[destination] = record
    }
    if updated != publications {
      savePublications(updated)
    }
  }

  func journalOperationDidEnd() {
    guard isSyncRequested || isDeletionRetryRequested else { return }
    Task { await processRequests() }
  }

  private func processRequests() async {
    guard !syncing, !PersistenceController.isJournalOperationInProgress, publicationRecordError == nil else { return }
    syncing = true
    defer { syncing = false }
    while isSyncRequested || isDeletionRetryRequested {
      guard !PersistenceController.isJournalOperationInProgress, publicationRecordError == nil else { return }
      let shouldSync = isSyncRequested
      isSyncRequested = false
      isDeletionRetryRequested = false
      await sendPendingDeletions()
      if shouldSync {
        for id in serverStore.servers.map(\.id) {
          guard !PersistenceController.isJournalOperationInProgress else {
            isSyncRequested = true
            break
          }
          if let server = serverStore.servers.first(where: { $0.id == id }) {
            await syncServer(server)
          }
        }
      }
    }
  }

  private func syncServer(_ server: LeaderboardServer) async {
    let destination = Destination(serverID: server.id, endpoint: server.endpoint, deviceID: deviceID(server.host))
    let shouldPublish = server.isActive
    var record = publications[destination] ?? PublicationRecord(nickname: server.nickname)
    guard shouldPublish || !record.tracked.isEmpty else {
      logSkipped(server)
      return
    }

    let persistence = persistence()
    let context: NSManagedObjectContext
    let ingestions: [Ingestion]
    do {
      context = try persistence.journalEditContext()
      ingestions = try PersistenceController.getPersonalIngestions(from: server.startsAt, to: server.expiresAt, in: context)
    } catch {
      reportSyncError(server, "Could not read journal entries. \(error.localizedDescription)")
      return
    }

    let eligibleIdentifiers = Set(ingestions.compactMap(\.identifier))
    let stale = record.tracked.subtracting(eligibleIdentifiers)
    if !stale.isEmpty {
      record.tracked.subtract(stale)
      record.pendingDeletions.formUnion(stale)
      save(record, for: destination)
      isDeletionRetryRequested = true
    }

    guard shouldPublish else {
      logSkipped(server)
      return
    }

    let unidentified = ingestions.filter { $0.identifier == nil }
    if !unidentified.isEmpty {
      unidentified.forEach { $0.identifier = UUID() }
      do {
        try PersistenceController.withJournalStoreWrite {
          try PersistenceController.saveJournalChanges(in: context)
        }
      } catch {
        reportSyncError(server, "Could not save journal entry identifiers. \(error.localizedDescription)")
        return
      }
    }

    // A pending delete uses the same remote entry key as any upload to this endpoint under this device ID.
    let pendingRemoteIDs = Set(publications
      .filter { $0.key.endpoint == destination.endpoint && $0.key.deviceID == destination.deviceID }
      .values.flatMap { $0.pendingDeletions.map(\.leaderboardId) })
    let upload = ingestions.compactMap { ingestion -> (UUID, LeaderboardEntryPayload)? in
      guard let identifier = ingestion.identifier, !pendingRemoteIDs.contains(identifier.leaderboardId) else { return nil }
      return (identifier, entryPayload(
        ingestion: ingestion, identifier: identifier, deviceId: destination.deviceID, nickname: server.nickname))
    }

    guard !upload.isEmpty else {
      if ingestions.isEmpty {
        markSynced(server, status: "success")
        logEntry("Sync complete. No ingestions in window.", server: server)
      }
      return
    }

    // Persist before sending, since a publish can succeed server-side before the response reaches this device.
    let identifiers = Set(upload.map { $0.0 })
    record.nickname = server.nickname
    record.tracked.formUnion(identifiers.subtracting(record.retained))
    save(record, for: destination)
    guard publicationRecordError == nil else { return }

    let revision = journalRevision
    let result = await client.submitBatch(baseURL: destination.endpoint, entries: upload.map { $0.1 })
    guard revision == journalRevision else { return }
    if let failure = result.failureDescription {
      reportSyncError(server, failure)
      return
    }

    // While the request was in flight, a journal deletion could have queued some of these identifiers.
    if var latestRecord = publications[destination] {
      latestRecord.tracked.formUnion(identifiers.subtracting(latestRecord.pendingDeletions))
      latestRecord.retained.subtract(identifiers)
      save(latestRecord, for: destination)
    }
    markSynced(server, status: "success")
    logEntry("Synced \(upload.count) entries", server: server)
  }

  private func sendPendingDeletions() async {
    for (destination, record) in publications {
      for identifier in record.pendingDeletions {
        guard !PersistenceController.isJournalOperationInProgress else {
          isDeletionRetryRequested = true
          return
        }

        let payload = deletionPayload(identifier: identifier, destination: destination, nickname: record.nickname)
        let result = await client.submitDelete(baseURL: destination.endpoint, entry: payload)
        if let failure = result.failureDescription {
          let message = "Could not remove a leaderboard entry. \(failure)"
          deletionError = "\(record.nickname) · \(message)"
          logEntry(message, serverID: destination.serverID, isError: true)
        } else if var latestRecord = publications[destination] {
          latestRecord.pendingDeletions.remove(identifier)
          save(latestRecord, for: destination)
        }
      }
    }
  }

  private func save(_ record: PublicationRecord, for destination: Destination) {
    var updated = publications
    updated[destination] = record.isEmpty ? nil : record
    if updated != publications {
      savePublications(updated)
    }
  }

  private func savePublications(_ updated: [Destination: PublicationRecord]) {
    guard publicationRecordError == nil else { return }
    do {
      defaults.set(try JSONEncoder().encode(updated), forKey: Self.publicationsKey)
      publications = updated
      updatePendingDeletionCount()
    } catch {
      publicationRecordError = "Could not save leaderboard publications. \(error.localizedDescription)"
    }
  }

  private func updatePendingDeletionCount() {
    pendingDeletionCount = publications.values.reduce(0) { $0 + $1.pendingDeletions.count }
    if pendingDeletionCount == 0 {
      deletionError = nil
    }
  }

  private func logSkipped(_ server: LeaderboardServer) {
    if server.isPaused {
      logEntry("Skipped: paused", server: server)
    } else if server.isExpired {
      logEntry("Skipped: expired", server: server)
    } else {
      logEntry("Skipped: waiting for start time", server: server)
    }
  }

  private func markSynced(_ server: LeaderboardServer, status: String) {
    guard serverStore.servers.contains(where: { $0.id == server.id && $0.endpoint == server.endpoint }) else { return }
    serverStore.markSynced(id: server.id, status: status)
  }

  private func reportSyncError(_ server: LeaderboardServer, _ detail: String) {
    markSynced(server, status: "failed")
    logEntry("Sync failed. \(detail)", server: server, isError: true)
  }

  private func deletionPayload(
    identifier: UUID, destination: Destination, nickname: String
  ) -> LeaderboardEntryPayload {
    LeaderboardEntryPayload(
      Id: destination.deviceID,
      Nickname: nickname,
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

  private func entryPayload(
    ingestion: Ingestion, identifier: UUID, deviceId: String, nickname: String
  ) -> LeaderboardEntryPayload {
    let customUnitDose = ingestion.customUnitDose
    let timeEpoch = Int64(ingestion.timeUnwrapped.timeIntervalSince1970)
    let endTimeEpoch = Int64((ingestion.endTime ?? ingestion.timeUnwrapped).timeIntervalSince1970)
    let creationEpoch = Int64((ingestion.creationDate ?? ingestion.timeUnwrapped).timeIntervalSince1970)
    let category = persistence().primaryCategory(for: ingestion.substanceNameUnwrapped) ?? ""
    let ingestionPayload = LeaderboardIngestionPayload(
      Id: identifier.leaderboardId,
      SubstanceName: ingestion.substanceNameUnwrapped,
      Time: timeEpoch,
      EndTime: endTimeEpoch,
      CreationDate: creationEpoch,
      AdministrationRoute: ingestion.administrationRouteUnwrapped.rawValue,
      // Custom unit ingestions store the number of units; servers compare amounts of the substance itself
      Dose: ingestion.pureSubstanceDose ?? 0.0,
      IsDoseAnEstimate: ingestion.isEstimate || customUnitDose?.customUnit.isEstimate == true ? 1 : 0,
      EstimatedDoseStandardDeviation: ingestion.pureSubstanceEstimatedDoseStandardDeviation ?? 0,
      Units: ingestion.pureUnits,
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

  private func logEntry(_ message: String, server: LeaderboardServer, isError: Bool = false) {
    logEntry(message, serverID: server.id, isError: isError)
  }

  private func logEntry(_ message: String, serverID: UUID, isError: Bool) {
    let entry = SyncLogEntry(date: Date(), serverID: serverID, message: message, isError: isError)
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
