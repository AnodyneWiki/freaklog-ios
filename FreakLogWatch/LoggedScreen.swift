import SwiftUI

// Shown over the app while logging: waits for the iPhone, then confirms with a chance to undo
struct LoggedScreen: View {
  let logging: QuickLogModel.Logging

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        icon
          .font(.system(size: 40))
          .frame(height: 48)
        Text(title)
          .font(.headline)
        Text(doseText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        if let detail {
          Text(detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        if isDone {
          Button("Undo", role: .destructive) {
            model.undo()
          }
          .padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .toolbar(isDone ? .visible : .hidden, for: .navigationBar)
    .interactiveDismissDisabled(logging.outcome == nil)
    .task(id: logging.outcome) {
      // Leaves time to undo before returning to the suggestions
      guard isDone else { return }
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      if model.logging?.id == logging.id {
        model.logging = nil
      }
    }
  }

  @EnvironmentObject private var model: QuickLogModel

  private var isDone: Bool {
    logging.outcome == .logged || logging.outcome == .queued
  }

  private var title: String {
    switch logging.outcome {
    case .none:
      "Logging…"
    case .logged, .queued:
      "Logged"
    case .failed:
      "Couldn't Log"
    }
  }

  // "100 mg MDMA"
  private var doseText: String {
    let suggestion = logging.request.suggestion
    return "\(suggestion.description(of: logging.request.dose)) \(suggestion.displayName)"
  }

  private var detail: String? {
    switch logging.outcome {
    case .queued:
      "It's added to your journal once your iPhone is reachable."
    case .failed(let message):
      message
    case .none, .logged:
      nil
    }
  }

  @ViewBuilder
  private var icon: some View {
    switch logging.outcome {
    case .none:
      ProgressView()
    case .logged:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .queued:
      Image(systemName: "clock.badge.checkmark.fill")
        .symbolRenderingMode(.multicolor)
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
    }
  }

}
