import Foundation
import WatchConnectivity

// MARK: - LogOutcome

enum LogOutcome: Equatable {
  // The iPhone saved it
  case logged
  // Queued until the iPhone is reachable
  case queued
  case failed(String)
}

// MARK: - WatchSession

// The watch's link to the iPhone app, which owns the journal. It holds the quick log suggestions the iPhone
// last sent and sends log requests: as a message when the iPhone is reachable, else queued as a transfer.
@MainActor
final class WatchSession: NSObject, ObservableObject {
  static let shared = WatchSession()

  @Published private(set) var suggestions: [WatchSuggestion] = []
  // False until the iPhone sent its suggestions once
  @Published private(set) var hasSuggestionsFromPhone = false
  @Published private(set) var queuedCount = 0

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  // Asks the iPhone for its current suggestions, launching its app in the background if needed
  func refresh() {
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else { return }
    session.sendMessage([WatchQuickLog.refreshKey: true]) { reply in
      Task { @MainActor in
        self.receive(reply)
      }
    } errorHandler: { _ in }
  }

  func log(_ request: WatchLogRequest) async -> LogOutcome {
    guard let data = try? WatchQuickLog.encode(request) else { return .failed("The dose couldn't be read") }
    let message = [WatchQuickLog.logKey: data]
    guard let reply = await send(message) else {
      // The iPhone logs a request only once, in case the message arrived after all
      WCSession.default.transferUserInfo(message)
      updateQueuedCount()
      return .queued
    }
    if let error = reply[WatchQuickLog.errorKey] as? String {
      return .failed(error)
    }
    return .logged
  }

  func undo(_ request: WatchLogRequest) async {
    let queuedTransfer = WCSession.default.outstandingUserInfoTransfers.first { transfer in
      WatchQuickLog.decode(WatchLogRequest.self, from: transfer.userInfo[WatchQuickLog.logKey])?.id == request.id
    }
    if let queuedTransfer {
      queuedTransfer.cancel()
    } else {
      let message = [WatchQuickLog.undoKey: request.ingestionIdentifiers.map(\.uuidString)]
      if await send(message) == nil {
        WCSession.default.transferUserInfo(message)
      }
    }
    updateQueuedCount()
  }

  // The reply, or nil if the iPhone isn't reachable or didn't answer
  private func send(_ message: [String: Any]) async -> [String: Any]? {
    let session = WCSession.default
    // Right after the app opens the iPhone shows as unreachable for a moment
    for _ in 0 ..< 10 where !session.isReachable {
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    guard session.activationState == .activated, session.isReachable else { return nil }
    return await withCheckedContinuation { continuation in
      session.sendMessage(message) { reply in
        continuation.resume(returning: reply)
      } errorHandler: { _ in
        continuation.resume(returning: nil)
      }
    }
  }

  private func receive(_ context: [String: Any]) {
    guard let suggestions = WatchQuickLog.decode([WatchSuggestion].self, from: context[WatchQuickLog.suggestionsKey])
    else { return }
    self.suggestions = suggestions
    hasSuggestionsFromPhone = true
  }

  private func updateQueuedCount() {
    queuedCount = WCSession.default.outstandingUserInfoTransfers.filter(\.isTransferring).count
  }
}

// MARK: WCSessionDelegate

extension WatchSession: WCSessionDelegate {
  nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
    let context = session.receivedApplicationContext
    Task { @MainActor in
      receive(context)
      updateQueuedCount()
      refresh()
    }
  }

  nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in
      receive(applicationContext)
    }
  }

  nonisolated func session(_: WCSession, didFinish _: WCSessionUserInfoTransfer, error _: Error?) {
    Task { @MainActor in
      updateQueuedCount()
    }
  }

  nonisolated func sessionReachabilityDidChange(_: WCSession) {
    Task { @MainActor in
      refresh()
    }
  }
}
