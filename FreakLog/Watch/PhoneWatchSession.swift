import CoreData
import UIKit
import WatchConnectivity

// MARK: - PhoneWatchSession

// Serves the watch app: keeps its quick log suggestions in step with the journal and logs what it sends.
// A message from the watch launches the app in the background, so this is activated at launch.
@MainActor
final class PhoneWatchSession: NSObject {
  static let shared = PhoneWatchSession()

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
    retryPendingUndos()
    let context = PersistenceController.shared.viewContext
    let center = NotificationCenter.default
    for name in [NSManagedObjectContext.didSaveObjectsNotification, NSManagedObjectContext.didMergeChangesObjectIDsNotification] {
      center.addObserver(forName: name, object: context, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.scheduleSuggestionsUpdate()
        }
      }
    }
  }

  func retryPendingUndos() {
    WatchQuickLogging.retryPendingUndos()
  }

  private var lastSentSuggestions: Data?
  private var pendingUpdate: Task<Void, Never>?

  // Saves often come in bursts, e.g. while editing or importing
  private func scheduleSuggestionsUpdate() {
    pendingUpdate?.cancel()
    pendingUpdate = Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard !Task.isCancelled else { return }
      sendSuggestions()
    }
  }

  private func sendSuggestions() {
    let session = WCSession.default
    guard
      session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
      let data = try? WatchQuickLog.encode(WatchQuickLogging.suggestions()),
      data != lastSentSuggestions
    else { return }
    do {
      try session.updateApplicationContext([WatchQuickLog.suggestionsKey: data])
      lastSentSuggestions = data
    } catch {
      print("Failed to send watch suggestions: \(error)")
    }
  }

  private func handle(_ message: [String: Any]) -> [String: Any] {
    let kind: WatchRequestKind
    if message[WatchQuickLog.logKey] != nil {
      kind = .log
    } else if message[WatchQuickLog.undoKey] != nil {
      kind = .undo
    } else if message[WatchQuickLog.refreshKey] != nil,
      let data = try? WatchQuickLog.encode(WatchQuickLogging.suggestions())
    {
      return [WatchQuickLog.suggestionsKey: data]
    } else {
      return [WatchQuickLog.errorKey: WatchQuickLogError.invalidRequest.localizedDescription]
    }

    let id = (message[WatchQuickLog.requestIDKey] as? String).flatMap(UUID.init(uuidString:))
    guard
      message[WatchQuickLog.logKey] == nil || message[WatchQuickLog.undoKey] == nil,
      let request = WatchRequest(kind: kind, payload: message[kind.messageKey]),
      message[WatchQuickLog.requestIDKey] == nil || id == request.id
    else {
      return reply(id: id, kind: kind, status: .rejected, detail: WatchQuickLogError.invalidRequest.localizedDescription)
    }

    // Webhooks and leaderboards may continue after a background delivery has been acknowledged.
    let backgroundTask = UIApplication.shared.beginBackgroundTask()
    defer {
      Task {
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        UIApplication.shared.endBackgroundTask(backgroundTask)
      }
    }

    do {
      switch request {
      case .log(let log):
        let status = try WatchQuickLogging.log(log)
        let detail = status == .undone ? "This watch quick log was already undone" : nil
        return reply(id: log.id, kind: kind, status: status, detail: detail)
      case .undo(let undo):
        try WatchQuickLogging.undo(undo)
        return reply(id: undo.id, kind: kind, status: .undone)
      }
    } catch let error as WatchQuickLogError {
      return reply(id: request.id, kind: kind, status: .rejected, detail: error.localizedDescription)
    } catch {
      return reply(id: request.id, kind: kind, status: .retry, detail: error.localizedDescription)
    }
  }

  private func reply(id: UUID?, kind: WatchRequestKind, status: WatchAcknowledgement.Status, detail: String? = nil)
    -> [String: Any]
  {
    var reply: [String: Any] = [:]
    if let id, let encoded = try? WatchQuickLog.encode(
      WatchAcknowledgement(id: id, kind: kind, status: status, message: detail))
    {
      reply[WatchQuickLog.acknowledgementKey] = encoded
    }
    // Older watches still expect an error string or an empty successful reply.
    reply[WatchQuickLog.errorKey] = detail
    return reply
  }
}

// MARK: WCSessionDelegate

extension PhoneWatchSession: WCSessionDelegate {
  nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
    Task { @MainActor in
      sendSuggestions()
    }
  }

  nonisolated func sessionDidBecomeInactive(_: WCSession) { }

  // After switching to another watch
  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  // E.g. after the watch app was installed
  nonisolated func sessionWatchStateDidChange(_: WCSession) {
    Task { @MainActor in
      lastSentSuggestions = nil
      sendSuggestions()
    }
  }

  nonisolated func session(
    _: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void)
  {
    Task { @MainActor in
      replyHandler(handle(message))
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    Task { @MainActor in
      let reply = handle(userInfo)
      if let acknowledgement = reply[WatchQuickLog.acknowledgementKey] as? Data {
        session.transferUserInfo([WatchQuickLog.acknowledgementKey: acknowledgement])
      } else if let error = reply[WatchQuickLog.errorKey] as? String {
        print("Queued watch request failed: \(error)")
      }
    }
  }
}
