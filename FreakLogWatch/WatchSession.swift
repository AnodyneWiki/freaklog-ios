import Combine
import Foundation
import WatchConnectivity

enum LogOutcome: Equatable {
  case logged
  case queued
  case undone
  case undoQueued
  case failed(String)
}

// The iPhone owns the journal. The Watch retains requests through reconnects and relaunches.
@MainActor
final class WatchSession: NSObject, ObservableObject {
  static let shared = WatchSession()

  @Published private(set) var suggestions: [WatchSuggestion] = []
  @Published private(set) var hasSuggestionsFromPhone = false
  @Published private(set) var queuedCount = 0
  @Published private(set) var rejections: [WatchRequestOutbox.Rejection] = []
  @Published private(set) var latestAcknowledgement: WatchAcknowledgement?
  @Published private(set) var queueError: String?
  @Published private(set) var routineSnapshot: RoutineQuickSnapshot = .empty
  @Published private(set) var pendingRoutineIDs: Set<UUID> = []
  @Published private(set) var completedRoutineIDs: Set<UUID> = []

  func activate() {
    loadOutbox()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func refresh() {
    loadOutbox()
    flush()
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else { return }
    session.sendMessage([WatchQuickLog.refreshKey: true]) { reply in
      Task { @MainActor in
        self.receiveSuggestions(reply)
      }
    } errorHandler: { _ in }
  }

  func log(_ request: WatchLogRequest) async -> LogOutcome {
    await submit(.log(request))
  }

  func undo(_ request: WatchLogRequest) async -> LogOutcome {
    await submit(.undo(WatchUndoRequest(log: request)))
  }

  func markTaken(_ action: RoutineQuickAction) async -> LogOutcome {
    let request = RoutineTakenRequest(action: action, recordedAt: .now)
    guard !pendingRoutineIDs.contains(request.id) else { return .queued }
    return await submit(.routineTaken(request))
  }

  func dismissRejection(_ id: UUID) {
    do {
      try outbox?.dismissRejection(id)
      updateQueue()
    } catch {
      reportQueueError(error)
    }
  }

  func handleBackgroundDelivery() async {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    while !Task.isCancelled && (session.activationState == .notActivated || session.hasContentPending) {
      try? await Task.sleep(for: .milliseconds(100))
    }
    await Task.yield()
  }

  static func outcome(for acknowledgement: WatchAcknowledgement) -> LogOutcome {
    switch acknowledgement.status {
    case .saved: .logged
    case .undone: .undone
    case .retry: queuedOutcome(for: acknowledgement.kind)
    case .rejected: .failed(acknowledgement.message ?? "Your iPhone rejected the request")
    }
  }

  private static let outboxFile = URL.applicationSupportDirectory.appendingPathComponent("WatchQuickLogOutbox.json")
  private var outbox: WatchRequestOutbox?
  private var inFlight: [UUID: WatchRequestKind] = [:]
  private var lastTransfer: [UUID: (kind: WatchRequestKind, date: Date)] = [:]
  private var retryTask: Task<Void, Never>?
  private static let retryInterval: TimeInterval = 15

  private static func queuedOutcome(for kind: WatchRequestKind) -> LogOutcome {
    kind == .undo ? .undoQueued : .queued
  }

  private func loadOutbox() {
    guard outbox == nil else { return }
    do {
      outbox = try WatchRequestOutbox(file: Self.outboxFile)
      updateQueue()
    } catch {
      reportQueueError(error)
    }
  }

  private func submit(_ request: WatchRequest) async -> LogOutcome {
    loadOutbox()
    guard outbox != nil else { return .failed("The Watch queue couldn't be opened") }
    do {
      try outbox?.enqueue(request)
      updateQueue()
    } catch {
      reportQueueError(error)
      return .failed("The request couldn't be saved on your Watch")
    }
    if request.kind == .undo, WCSession.isSupported(), WCSession.default.activationState == .activated {
      cancelTransfers(id: request.id, kind: .log)
    }
    return await deliver(request)
  }

  private func deliver(_ request: WatchRequest) async -> LogOutcome {
    let queued = Self.queuedOutcome(for: request.kind)
    guard WCSession.isSupported(), outbox?.pending[request.id] == request else { return queued }
    let session = WCSession.default
    guard session.activationState == .activated, inFlight[request.id] != request.kind else { return queued }
    guard let message = try? request.message() else {
      let acknowledgement = WatchAcknowledgement(
        id: request.id, kind: request.kind, status: .rejected, message: "The request couldn't be encoded")
      return receive(acknowledgement) ?? queued
    }

    inFlight[request.id] = request.kind
    defer {
      if inFlight[request.id] == request.kind {
        inFlight[request.id] = nil
      }
      scheduleRetry()
    }
    if session.isReachable,
       let reply = await send(message),
       let acknowledgement = WatchQuickLog.decode(WatchAcknowledgement.self, from: reply[WatchQuickLog.acknowledgementKey]),
       acknowledgement.id == request.id, acknowledgement.kind == request.kind
    {
      return receive(acknowledgement) ?? queued
    }

    // The interactive message may have committed with its reply lost. Keep the same request ID.
    guard outbox?.pending[request.id] == request else { return queued }
    let last = lastTransfer[request.id]
    let canTransfer = last?.kind != request.kind || last.map { Date().timeIntervalSince($0.date) >= Self.retryInterval } == true
    if canTransfer, session.activationState == .activated,
       !session.outstandingUserInfoTransfers.contains(where: { Self.request(in: $0.userInfo) == request })
    {
      session.transferUserInfo(message)
      lastTransfer[request.id] = (request.kind, Date())
    }
    return queued
  }

  private func send(_ message: [String: Any]) async -> [String: Any]? {
    await withCheckedContinuation { continuation in
      WCSession.default.sendMessage(message) { reply in
        continuation.resume(returning: reply)
      } errorHandler: { _ in
        continuation.resume(returning: nil)
      }
    }
  }

  @discardableResult
  private func receive(_ acknowledgement: WatchAcknowledgement) -> LogOutcome? {
    loadOutbox()
    guard outbox?.pending[acknowledgement.id]?.kind == acknowledgement.kind else { return nil }
    if acknowledgement.status == .retry {
      scheduleRetry()
      return Self.outcome(for: acknowledgement)
    }

    do {
      guard try outbox?.acknowledge(acknowledgement) == true else { return nil }
      if acknowledgement.kind == .routineTaken, acknowledgement.status == .saved {
        completedRoutineIDs.insert(acknowledgement.id)
      }
      lastTransfer[acknowledgement.id] = nil
      cancelTransfers(id: acknowledgement.id, kind: acknowledgement.kind)
      updateQueue()
      latestAcknowledgement = acknowledgement
      return Self.outcome(for: acknowledgement)
    } catch {
      reportQueueError(error)
      scheduleRetry()
      return nil
    }
  }

  private func cancelTransfers(id: UUID, kind: WatchRequestKind) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
    for transfer in WCSession.default.outstandingUserInfoTransfers {
      if Self.requestID(in: transfer.userInfo, kind: kind) == id {
        transfer.cancel()
      }
    }
  }

  private func flush() {
    guard let pending = outbox?.pending.values else { return }
    for request in pending {
      Task { await deliver(request) }
    }
    scheduleRetry()
  }

  private func scheduleRetry() {
    guard retryTask == nil, outbox?.pending.isEmpty == false else { return }
    retryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.retryInterval))
      guard !Task.isCancelled, let self else { return }
      retryTask = nil
      flush()
    }
  }

  private func receiveSuggestions(_ context: [String: Any]) {
    if let snapshot = WatchQuickLog.decode(RoutineQuickSnapshot.self, from: context[WatchQuickLog.routineSnapshotKey]) {
      routineSnapshot = snapshot
      completedRoutineIDs.formIntersection(snapshot.previews.compactMap { $0.action?.slot.receiptID })
    }
    guard let suggestions = WatchQuickLog.decode([WatchSuggestion].self, from: context[WatchQuickLog.suggestionsKey])
    else { return }
    self.suggestions = suggestions
    hasSuggestionsFromPhone = true
  }

  private func updateQueue() {
    queuedCount = outbox?.pending.count ?? 0
    rejections = outbox?.rejections ?? []
    pendingRoutineIDs = Set(outbox?.pending.values.filter { $0.kind == .routineTaken }.map(\.id) ?? [])
    queueError = nil
    if queuedCount == 0 {
      retryTask?.cancel()
      retryTask = nil
    }
  }

  private func reportQueueError(_ error: Error) {
    print("Watch quick log queue: \(error)")
    queueError = "Your Watch couldn't update the quick log queue."
  }

  private func recoverLegacyTransfers(_ transfers: [WCSessionUserInfoTransfer]) {
    guard outbox != nil else { return }
    for transfer in transfers {
      let info = transfer.userInfo
      guard info[WatchQuickLog.requestIDKey] == nil, let request = Self.request(in: info) else { continue }
      if outbox?.pending[request.id]?.kind == .undo || outbox?.rejections.contains(where: { $0.id == request.id }) == true {
        continue
      }
      do {
        try outbox?.enqueue(request)
      } catch {
        reportQueueError(error)
        return
      }
    }
    updateQueue()
  }

  private static func request(in info: [String: Any]) -> WatchRequest? {
    WatchRequest(kind: .log, payload: info[WatchQuickLog.logKey])
      ?? WatchRequest(kind: .undo, payload: info[WatchQuickLog.undoKey])
      ?? WatchRequest(kind: .routineTaken, payload: info[WatchQuickLog.routineTakenKey])
  }

  private static func requestID(in info: [String: Any], kind: WatchRequestKind) -> UUID? {
    guard info[kind.messageKey] != nil else { return nil }
    return (info[WatchQuickLog.requestIDKey] as? String).flatMap(UUID.init(uuidString:))
      ?? WatchRequest(kind: kind, payload: info[kind.messageKey])?.id
  }
}

extension WatchSession: WCSessionDelegate {
  nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
    let context = session.receivedApplicationContext
    Task { @MainActor in
      loadOutbox()
      receiveSuggestions(context)
      recoverLegacyTransfers(session.outstandingUserInfoTransfers)
      refresh()
    }
  }

  nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in
      receiveSuggestions(applicationContext)
    }
  }

  nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let acknowledgement = WatchQuickLog.decode(
      WatchAcknowledgement.self, from: userInfo[WatchQuickLog.acknowledgementKey])
    else { return }
    Task { @MainActor in
      receive(acknowledgement)
    }
  }

  nonisolated func session(_: WCSession, didFinish _: WCSessionUserInfoTransfer, error _: Error?) {
    Task { @MainActor in
      scheduleRetry()
    }
  }

  nonisolated func sessionReachabilityDidChange(_: WCSession) {
    Task { @MainActor in
      refresh()
    }
  }
}
