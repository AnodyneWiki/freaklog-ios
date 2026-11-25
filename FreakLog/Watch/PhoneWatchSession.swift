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
    Task { await WatchQuickLogging.retryPendingUndos() }
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

  // Returns the reply for the watch
  private func handle(_ message: [String: Any]) async -> [String: Any] {
    if message[WatchQuickLog.refreshKey] != nil {
      guard let data = try? WatchQuickLog.encode(WatchQuickLogging.suggestions()) else { return [:] }
      return [WatchQuickLog.suggestionsKey: data]
    }
    // Webhooks and leaderboards are sent after saving, which needs time when launched in the background
    let backgroundTask = UIApplication.shared.beginBackgroundTask()
    defer {
      Task {
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        UIApplication.shared.endBackgroundTask(backgroundTask)
      }
    }
    if let request = WatchQuickLog.decode(WatchLogRequest.self, from: message[WatchQuickLog.logKey]) {
      do {
        try WatchQuickLogging.log(request)
      } catch {
        PersistenceController.shared.viewContext.rollback()
        return [WatchQuickLog.errorKey: error.localizedDescription]
      }
    } else if let identifiers = message[WatchQuickLog.undoKey] as? [String] {
      do {
        let decoded = identifiers.compactMap(UUID.init(uuidString:))
        guard decoded.count == identifiers.count else { throw WatchQuickLogError.invalidUndo }
        try await WatchQuickLogging.undo(ingestionsWithIdentifiers: decoded)
      } catch {
        return [WatchQuickLog.errorKey: error.localizedDescription]
      }
    }
    return [:]
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
      replyHandler(await handle(message))
    }
  }

  // Logs and undos the watch queued while the iPhone wasn't reachable, in order
  nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    Task { @MainActor in
      if let error = await handle(userInfo)[WatchQuickLog.errorKey] as? String {
        print("Queued watch request failed: \(error)")
      }
    }
  }
}
