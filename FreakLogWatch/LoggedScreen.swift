import SwiftUI

// Shown over the app while logging: waits for the iPhone, then confirms with a chance to undo
struct LoggedScreen: View {
  let request: WatchLogRequest

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        icon
          .font(.system(size: 40))
          .frame(height: 48)
          .accessibilityHidden(true)
        Text(title)
          .font(.headline)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
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
        if canUndo {
          Button("Undo", role: .destructive) {
            model.undo()
          }
          .padding(.top, 4)
        }
        if outcome != nil {
          Button("Done") { model.logging = nil }
        }
      }
      .frame(maxWidth: .infinity)
    }
    .toolbar(outcome == nil ? .hidden : .visible, for: .navigationBar)
    .interactiveDismissDisabled(outcome == nil)
    .task(id: outcome) {
      // Never remove the only Undo action while somebody is reading the receipt.
      guard outcome == .undone || outcome == .undoQueued else { return }
      try? await Task.sleep(for: .seconds(5))
      if !Task.isCancelled, model.logging?.id == request.id {
        model.logging = nil
      }
    }
  }

  @EnvironmentObject private var model: QuickLogModel

  private var outcome: LogOutcome? {
    model.logging?.outcome
  }

  private var canUndo: Bool {
    outcome == .logged || outcome == .queued
  }

  private var title: String {
    switch outcome {
    case .none:
      model.logging?.kind == .undo ? "Undoing…" : "Logging…"
    case .logged:
      "Logged"
    case .queued:
      "Log Queued"
    case .undone:
      "Undone"
    case .undoQueued:
      "Undo Queued"
    case .failed:
      model.logging?.kind == .undo ? "Couldn't Undo" : "Couldn't Log"
    }
  }

  // "100 mg MDMA"
  private var doseText: String {
    let suggestion = request.suggestion
    return "\(suggestion.description(of: request.dose)) \(suggestion.displayName)"
  }

  private var detail: String? {
    switch outcome {
    case .queued, .undoQueued:
      "Waiting for your iPhone to confirm."
    case .failed(let message):
      message
    case .none, .logged, .undone:
      nil
    }
  }

  @ViewBuilder
  private var icon: some View {
    switch outcome {
    case .none:
      ProgressView()
    case .logged, .undone:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .queued, .undoQueued:
      Image(systemName: "clock")
        .foregroundStyle(.secondary)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
    }
  }

}
