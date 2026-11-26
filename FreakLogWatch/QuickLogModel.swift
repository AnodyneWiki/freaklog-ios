import SwiftUI
import WatchKit

// MARK: - QuickLogModel

// Logs from any screen and shows the result, then returns to the suggestions
@MainActor
final class QuickLogModel: ObservableObject {
  init(session: WatchSession) {
    self.session = session
  }

  struct Logging: Identifiable {
    let request: WatchLogRequest
    var kind: WatchRequestKind = .log
    // Nil while waiting for the iPhone
    var outcome: LogOutcome?

    var id: UUID {
      request.id
    }
  }

  @Published var path: [QuickLogDestination] = []
  @Published var logging: Logging?

  func log(_ dose: WatchDose, of suggestion: WatchSuggestion) {
    let request = WatchLogRequest(id: UUID(), suggestion: suggestion, dose: dose, time: Date())
    logging = Logging(request: request)
    Task {
      let outcome = await session.log(request)
      update(outcome, id: request.id, kind: .log)
    }
  }

  func undo() {
    guard let request = logging?.request else { return }
    logging?.kind = .undo
    logging?.outcome = nil
    Task {
      let outcome = await session.undo(request)
      update(outcome, id: request.id, kind: .undo)
    }
  }

  func acknowledge(_ acknowledgement: WatchAcknowledgement) {
    update(WatchSession.outcome(for: acknowledgement), id: acknowledgement.id, kind: acknowledgement.kind)
  }

  private func update(_ outcome: LogOutcome, id: UUID, kind: WatchRequestKind) {
    guard logging?.id == id, logging?.kind == kind, logging?.outcome != outcome else { return }
    if outcome == .queued || outcome == .undoQueued {
      guard logging?.outcome == nil else { return }
    }
    logging?.outcome = outcome
    switch outcome {
    case .logged, .undone:
      WKInterfaceDevice.current().play(.success)
      path = []
    case .queued, .undoQueued:
      WKInterfaceDevice.current().play(.click)
      path = []
    case .failed:
      WKInterfaceDevice.current().play(.failure)
    }
  }

  private let session: WatchSession

}

// MARK: - QuickLogDestination

enum QuickLogDestination: Hashable {
  case doses(WatchSuggestion)
  case otherDose(WatchSuggestion)
}
