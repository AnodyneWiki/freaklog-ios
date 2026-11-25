import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class WebhookTests: XCTestCase {
  func testNoteMessagesUseTheNoteLayout() {
    let settings = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "Sam",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(forNote: "Peaking", settings: settings), "Sam: Peaking")
    let anonymous = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(forNote: "Peaking", settings: anonymous), "Peaking")
  }

  func testIngestionMessagesKeepTheirLayout() {
    let data = WebhookManager.WebhookDataSnapshot(
      user: "",
      substance: "Caffeine",
      substanceDisplayName: "Caffeine",
      dose: 100,
      units: "mg",
      isEstimate: true,
      route: "oral",
      site: "",
      simpleSite: "",
      note: "")
    let settings = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "Sam",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(for: data, settings: settings), "Sam: ~100 mg Caffeine via oral")
  }

  func testSiteLabelsForJournalAndWebhookTemplates() {
    let context = PersistenceController(inMemory: true).viewContext
    let ingestion = Ingestion(context: context)
    let route = AdministrationRoute.intramuscular
    ingestion.administrationRoute = route.rawValue
    ingestion.administrationSite = "Left Deltoid"

    XCTAssertEqual(AdministrationSiteNameStyle.simple.label(for: ingestion.administrationSiteUnwrapped, route: route),
                   "Left shoulder")
    XCTAssertEqual(AdministrationSiteNameStyle.medical.label(for: ingestion.administrationSiteUnwrapped, route: route),
                   "Left deltoid")
    let settings = WebhookManager.WebhookSettingsSnapshot(
      template: "[{site} / {site_simple}]",
      noteTemplate: "",
      username: "",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(for: .init(ingestion: ingestion), settings: settings),
                   "left deltoid / left shoulder")
    XCTAssertEqual(ingestion.administrationSite, "Left Deltoid")

    ingestion.administrationSite = "Custom site"
    XCTAssertEqual(WebhookService.content(for: .init(ingestion: ingestion), settings: settings),
                   "custom site / custom site")
    ingestion.administrationSite = nil
    XCTAssertEqual(WebhookService.content(for: .init(ingestion: ingestion), settings: settings), "")
  }

  func testTimedNoteMessagesAreDeletedWithTheNote() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let preset = WebhookPreset(context: context)
    preset.url = "https://example.com/webhook"
    let note = TimedNote(context: context)
    note.note = "Peaking"
    let message = WebhookMessage(context: context)
    message.messageId = "1"
    message.webhookPreset = preset
    message.timedNote = note
    try context.save()
    XCTAssertEqual(note.webhookMessagesSorted, [message])

    context.delete(note)
    try context.save()
    XCTAssertEqual(try context.count(for: WebhookMessage.fetchRequest()), 0)
    XCTAssertTrue(preset.messages?.count == 0)
  }

  func testCleanupDestinationsSurviveCascadesAndFailedRequests() async throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let preset = WebhookPreset(context: context)
    preset.url = "https://example.com/preset"
    let note = TimedNote(context: context)
    let message = WebhookMessage(context: context)
    message.messageId = "11"
    message.destinationURL = "https://example.com/original"
    message.webhookPreset = preset
    message.timedNote = note
    try context.save()

    WebhookManager.stageMessageDeletion(for: [], timedNotes: [note], in: context)
    context.delete(note)
    context.rollback()
    XCTAssertEqual(try context.count(for: WebhookDeletion.fetchRequest()), 0)

    try WebhookManager.stageAllPresetDeletion(in: context)
    context.delete(note)
    try context.save()
    XCTAssertEqual(try context.count(for: WebhookMessage.fetchRequest()), 0)

    let first = WebhookManager(container: persistence.container, deleteMessage: { url, id in
      XCTAssertEqual(url, "https://example.com/original")
      XCTAssertEqual(id, "11")
      return false
    })
    let result = await first.retryPendingDeletions()
    XCTAssertFalse(result)
    XCTAssertEqual(try context.count(for: WebhookDeletion.fetchRequest()), 1)

    var retries = 0
    let restarted = WebhookManager(container: persistence.container, deleteMessage: { url, id in
      XCTAssertEqual(url, "https://example.com/original")
      XCTAssertEqual(id, "11")
      retries += 1
      return true
    })
    let retryResult = await restarted.retryPendingDeletions()
    XCTAssertTrue(retryResult)
    XCTAssertEqual(retries, 1)
    XCTAssertEqual(try context.count(for: WebhookDeletion.fetchRequest()), 0)
  }

  func testUpdatesKeepLatestContentDuringPostAndPatch() async throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let preset = WebhookPreset(context: context)
    preset.url = "https://example.com/webhook"
    let note = TimedNote(context: context)
    note.note = "Original"
    try context.save()
    let transport = GatedTransport()
    let manager = WebhookManager(container: persistence.container, sendMessage: transport.send)

    manager.sendWebhooks(for: note, presetObjectIDs: [preset.objectID])
    let posted = await transport.waitForRequests(1)
    XCTAssertTrue(posted)
    guard posted else { return }
    XCTAssertNil(transport.requests[0].messageId)

    note.note = "Edited during POST"
    try context.save()
    manager.editWebhookMessages(for: note)
    transport.succeed(0, messageId: "9")

    let patched = await transport.waitForRequests(2)
    XCTAssertTrue(patched)
    guard patched else { return }
    XCTAssertEqual(transport.requests[1].messageId, "9")
    XCTAssertTrue(transport.requests[1].content.contains("Edited during POST"))

    for content in ["Intermediate", "Final"] {
      note.note = content
      try context.save()
      manager.editWebhookMessages(for: note)
    }
    XCTAssertEqual(transport.requests.count, 2)
    transport.succeed(1, messageId: "9")

    let updated = await transport.waitForRequests(3)
    XCTAssertTrue(updated)
    guard updated else { return }
    XCTAssertEqual(transport.requests[2].messageId, "9")
    XCTAssertTrue(transport.requests[2].content.contains("Final"))
    transport.succeed(2, messageId: "9")
  }

  func testLatePostIDIsCleanedUpWhenItsOwnerDisappears() async throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let preset = WebhookPreset(context: context)
    preset.url = "https://example.com/webhook"
    let note = TimedNote(context: context)
    note.note = "Original"
    try context.save()

    let transport = GatedTransport()
    let deleted = expectation(description: "Late delivery cleaned up")
    let manager = WebhookManager(
      container: persistence.container,
      sendMessage: transport.send,
      deleteMessage: { url, messageId in
        XCTAssertEqual(url, "https://example.com/webhook")
        XCTAssertEqual(messageId, "8")
        deleted.fulfill()
        return false
      },
      reportFailure: { _ in })

    manager.sendWebhooks(for: note, presetObjectIDs: [preset.objectID])
    let posted = await transport.waitForRequests(1)
    XCTAssertTrue(posted)
    guard posted else { return }
    WebhookManager.stageMessageDeletion(for: [], timedNotes: [note], in: context)
    context.delete(note)
    context.delete(preset)
    try context.save()
    transport.succeed(0, messageId: "8")

    await fulfillment(of: [deleted], timeout: 2)
    XCTAssertEqual(try context.count(for: WebhookMessage.fetchRequest()), 0)
    XCTAssertEqual(try context.count(for: WebhookDeletion.fetchRequest()), 1)
  }

  func testPostWithoutUsableResponseIsNotRetried() async {
    for lostResponse in [false, true] {
      var count = 0
      let result = await WebhookService.sendWebhookWithRetry(
        url: "https://example.com/webhook?thread_id=10&wait=false",
        content: "Test",
        loadData: { request in
          count += 1
          XCTAssertEqual(request.httpMethod, "POST")
          let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
          XCTAssertEqual(components?.queryItems?.filter { $0.name == "wait" }.map(\.value), ["true"])
          XCTAssertEqual(components?.queryItems?.first { $0.name == "thread_id" }?.value, "10")
          if lostResponse { throw URLError(.networkConnectionLost) }
          let url = try XCTUnwrap(request.url)
          let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil))
          return (Data(), response)
        })
      XCTAssertEqual(count, 1)
      XCTAssertFalse(result.success)
      XCTAssertEqual(result.error as? WebhookService.DeliveryError, .unknownDelivery)
    }
  }
}

@MainActor
private final class GatedTransport {
  struct Request {
    let content: String
    let messageId: String?
  }

  private(set) var requests: [Request] = []
  private var replies: [Int: CheckedContinuation<WebhookResult, Never>] = [:]

  func send(url: String, content: String, messageId: String?) async -> WebhookResult {
    await withCheckedContinuation { reply in
      replies[requests.count] = reply
      requests.append(Request(content: content, messageId: messageId))
    }
  }

  func waitForRequests(_ count: Int) async -> Bool {
    for _ in 0..<100 {
      if requests.count >= count { return true }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
  }

  func succeed(_ index: Int, messageId: String) {
    replies.removeValue(forKey: index)?.resume(returning: WebhookResult(success: true, messageId: messageId, error: nil))
  }
}

@MainActor
final class LeaderboardSyncTests: XCTestCase {
  func testExplicitDeletionUsesPreviouslySyncedLegacyDestination() async throws {
    let defaultsName = "LeaderboardSyncTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let persistence = PersistenceController(inMemory: true)
    let servers = LeaderboardServerStore(defaults: defaults)
    let server = makeServer()
    servers.add(server)
    servers.markSynced(id: server.id, status: "success")
    servers.add(LeaderboardServer(host: "never-synced.example", nickname: "Never synced", startsAt: .now))

    let client = TestClient()
    let manager = LeaderboardSyncManager(
      client: client, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "original" })
    servers.delete(id: server.id)
    let identifier = UUID()
    await manager.notifyDeletion(identifiers: [identifier])

    XCTAssertEqual(client.deletions.map(\.endpoint), [server.endpoint])
    XCTAssertEqual(client.deletions.first?.entry.Id, "original")
    XCTAssertEqual(client.deletions.first?.entry.Ingestion.Id, identifier.leaderboardId)
  }

  func testDeletionRetriesAtOriginalDestinationAfterServerRemoval() async throws {
    let defaultsName = "LeaderboardSyncTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let persistence = PersistenceController(inMemory: true)
    let servers = LeaderboardServerStore(defaults: defaults)
    let server = makeServer()
    servers.add(server)
    servers.add(LeaderboardServer(host: "other.example", nickname: "Other", startsAt: Date.now.addingTimeInterval(-60)))
    let ingestion = makeIngestion(in: persistence.viewContext)
    try persistence.viewContext.save()
    let identifier = try XCTUnwrap(ingestion.identifier)

    let client = TestClient()
    let manager = LeaderboardSyncManager(
      client: client, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "original" })
    await manager.syncAll()
    XCTAssertEqual(client.submissions.map(\.endpoint), [server.endpoint])

    servers.delete(id: server.id)
    persistence.viewContext.delete(ingestion)
    try persistence.viewContext.save()
    client.deleteResult = .httpError(503)
    await manager.notifyDeletion(identifiers: [identifier, UUID()])
    XCTAssertEqual(manager.pendingDeletionCount, 1)
    XCTAssertEqual(client.deletions.map(\.endpoint), [server.endpoint])
    XCTAssertTrue(manager.log.contains { $0.isError && $0.message.contains("503") })

    let retryClient = TestClient()
    let restarted = LeaderboardSyncManager(
      client: retryClient, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "restored" })
    XCTAssertEqual(restarted.pendingDeletionCount, 1)
    await restarted.retryPendingDeletions()
    XCTAssertEqual(retryClient.deletions.map(\.endpoint), [server.endpoint])
    XCTAssertEqual(retryClient.deletions.first?.entry.Id, "original")
    XCTAssertEqual(retryClient.deletions.first?.entry.Ingestion.Id, identifier.leaderboardId)
    XCTAssertEqual(restarted.pendingDeletionCount, 0)
  }

  func testRemovesPublishedEntriesLeavingTheWindowOrPersonalQuery() async throws {
    let defaultsName = "LeaderboardSyncTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let servers = LeaderboardServerStore(defaults: defaults)
    let server = makeServer()
    servers.add(server)
    let moved = makeIngestion(in: context)
    moved.identifier = nil
    let attributedToGuest = makeIngestion(in: context)
    try context.save()

    let client = TestClient()
    let manager = LeaderboardSyncManager(
      client: client, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "test-device" })
    await manager.syncAll()
    context.refreshAllObjects()
    let movedID = try XCTUnwrap(moved.identifier)
    let guestID = try XCTUnwrap(attributedToGuest.identifier)
    XCTAssertFalse(context.hasChanges)
    XCTAssertEqual(Set(client.submissions.flatMap(\.entries).map { $0.Ingestion.Id }), [movedID.leaderboardId, guestID.leaderboardId])

    moved.time = server.startsAt.addingTimeInterval(-60)
    attributedToGuest.consumerName = "Guest"
    try context.save()
    await manager.syncAll()

    XCTAssertEqual(client.submissions.count, 1)
    XCTAssertEqual(Set(client.deletions.map { $0.entry.Ingestion.Id }), [movedID.leaderboardId, guestID.leaderboardId])
  }

  func testDeletionDuringPublicationWaitsForSubmission() async throws {
    let defaultsName = "LeaderboardSyncTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let persistence = PersistenceController(inMemory: true)
    let servers = LeaderboardServerStore(defaults: defaults)
    servers.add(makeServer())
    let context = persistence.viewContext
    let ingestion = makeIngestion(in: context)
    try context.save()
    let identifier = try XCTUnwrap(ingestion.identifier)
    let client = TestClient()
    let manager = LeaderboardSyncManager(
      client: client, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "test-device" })
    client.beforeBatchReturns = {
      context.delete(ingestion)
      do {
        try context.save()
      } catch {
        XCTFail("Couldn't save the deletion: \(error)")
        return
      }
      await manager.notifyDeletion(identifiers: [identifier])
      XCTAssertTrue(client.deletions.isEmpty)
      XCTAssertEqual(manager.pendingDeletionCount, 1)
    }

    await manager.syncAll()
    client.beforeBatchReturns = nil
    XCTAssertEqual(client.deletions.map { $0.entry.Ingestion.Id }, [identifier.leaderboardId])
    XCTAssertEqual(manager.pendingDeletionCount, 0)
  }

  func testReplacementKeepsRemoteEntriesUntilAnExplicitDeletion() async throws {
    let defaultsName = "LeaderboardSyncTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let persistence = PersistenceController(inMemory: true)
    let servers = LeaderboardServerStore(defaults: defaults)
    servers.add(makeServer())
    let context = persistence.viewContext
    let ingestion = makeIngestion(in: context)
    try context.save()
    let identifier = try XCTUnwrap(ingestion.identifier)
    let client = TestClient()
    let manager = LeaderboardSyncManager(
      client: client, serverStore: servers, persistence: { persistence }, defaults: defaults, deviceID: { _ in "test-device" })
    await manager.syncAll()

    context.delete(ingestion)
    try context.save()
    manager.journalWasReplaced()
    await manager.syncAll()
    XCTAssertTrue(client.deletions.isEmpty)

    await manager.notifyDeletion(identifiers: [identifier])
    XCTAssertEqual(client.deletions.map { $0.entry.Ingestion.Id }, [identifier.leaderboardId])
  }

  private func makeServer() -> LeaderboardServer {
    LeaderboardServer(host: "test.example", nickname: "Test", startsAt: Date.now.addingTimeInterval(-3600))
  }

  private func makeIngestion(in context: NSManagedObjectContext) -> Ingestion {
    let ingestion = Ingestion(context: context)
    ingestion.identifier = UUID()
    ingestion.substanceName = "Caffeine"
    ingestion.time = Date.now.addingTimeInterval(-1800)
    return ingestion
  }

  private final class TestClient: LeaderboardSyncClient {
    var submissions: [(endpoint: String, entries: [LeaderboardEntryPayload])] = []
    var deletions: [(endpoint: String, entry: LeaderboardEntryPayload)] = []
    var deleteResult = LeaderboardClientResult.success
    var beforeBatchReturns: (() async -> Void)?

    func submitBatch(baseURL: String, entries: [LeaderboardEntryPayload]) async -> LeaderboardClientResult {
      submissions.append((baseURL, entries))
      await beforeBatchReturns?()
      return .success
    }

    func submitDelete(baseURL: String, entry: LeaderboardEntryPayload) async -> LeaderboardClientResult {
      deletions.append((baseURL, entry))
      return deleteResult
    }
  }
}
