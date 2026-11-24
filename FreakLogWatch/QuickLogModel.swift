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
      guard logging?.id == request.id else { return }
      logging?.outcome = outcome
      switch outcome {
      case .logged, .queued:
        WKInterfaceDevice.current().play(.success)
        path = []
      case .failed:
        WKInterfaceDevice.current().play(.failure)
      }
    }
  }

  func undo() {
    guard let request = logging?.request else { return }
    logging = nil
    WKInterfaceDevice.current().play(.click)
    Task {
      await session.undo(request)
    }
  }

  private let session: WatchSession

}

// MARK: - QuickLogDestination

enum QuickLogDestination: Hashable {
  case doses(WatchSuggestion)
  case otherDose(WatchSuggestion)
}
