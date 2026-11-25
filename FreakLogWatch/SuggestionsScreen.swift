import SwiftUI

// MARK: - SuggestionsScreen

// The substances logged recently on the iPhone, latest first
struct SuggestionsScreen: View {
  var body: some View {
    NavigationStack(path: $model.path) {
      TimelineView(.periodic(from: .now, by: 60)) { context in
        quickLogList(at: context.date)
      }
      .navigationTitle("Quick Log")
      .navigationDestination(for: QuickLogDestination.self) { destination in
        switch destination {
        case .doses(let suggestion):
          DosesScreen(suggestion: suggestion)
        case .otherDose(let suggestion):
          OtherDoseScreen(suggestion: suggestion)
        }
      }
    }
    .sheet(item: $model.logging) { logging in
      LoggedScreen(request: logging.request)
    }
    .onReceive(session.$latestAcknowledgement) { acknowledgement in
      if let acknowledgement {
        model.acknowledge(acknowledgement)
      }
    }
  }

  @EnvironmentObject private var session: WatchSession
  @EnvironmentObject private var model: QuickLogModel
  @State private var routineError: String?

  private func quickLogList(at date: Date) -> some View {
    List {
      if session.suggestions.isEmpty, session.queuedCount == 0, session.rejections.isEmpty,
         session.queueError == nil, session.routineSnapshot.next(at: date) == nil,
         !session.routineSnapshot.phoneLocked {
        emptyView.listRowBackground(Color.clear)
      } else {
        routineSection(at: date)
      }
      ForEach(session.suggestions) { suggestion in
        NavigationLink(value: QuickLogDestination.doses(suggestion)) {
          SuggestionRow(suggestion: suggestion)
        }
      }
      if session.queuedCount > 0 {
        Section {
          Label(queuedText, systemImage: "clock")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
        }
      }
      if let error = session.queueError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.footnote)
      }
      ForEach(session.rejections) { rejection in
        VStack(alignment: .leading) {
          Text(rejection.request.kind == .undo ? "Couldn't Undo" : "Couldn't Log")
            .font(.headline)
          Text(rejection.message)
            .font(.footnote)
          Button("Dismiss") {
            session.dismissRejection(rejection.id)
          }
          .font(.footnote)
        }
      }
    }
  }

  @ViewBuilder
  private func routineSection(at date: Date) -> some View {
    if let routine = session.routineSnapshot.next(at: date) {
      Section {
        if date >= routine.dayStart {
          Text(routine.scheduledAt, format: .dateTime.hour().minute())
        } else {
          Text(routine.scheduledAt, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
        if let action = routine.action, date >= routine.dayStart {
          let id = action.slot.receiptID
          if session.completedRoutineIDs.contains(id) {
            Label("Taken", systemImage: "checkmark")
          } else if session.pendingRoutineIDs.contains(id) {
            Label("Waiting for iPhone", systemImage: "clock")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Button {
              Task {
                routineError = nil
                if case .failed(let message) = await session.markTaken(action),
                   !session.rejections.contains(where: { $0.id == id }) {
                  routineError = message
                }
              }
            } label: {
              Label("Mark Taken", systemImage: "checkmark")
            }
          }
        } else if date >= routine.dayStart {
          Text("Open FreakLog on your iPhone to log this routine.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let routineError {
          Text(routineError)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Next Routine")
      }
    } else if session.routineSnapshot.phoneLocked {
      Section("Next Routine") {
        Text("Open FreakLog on your iPhone to log routines.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var queuedText: String {
    session.queuedCount == 1
      ? "1 request awaiting iPhone confirmation"
      : "\(session.queuedCount) requests awaiting iPhone confirmation"
  }

  @ViewBuilder
  private var emptyView: some View {
    if session.hasSuggestionsFromPhone {
      VStack(alignment: .leading, spacing: 6) {
        Label("No Recent Ingestions", systemImage: "list.bullet").font(.headline)
        Text("Log an ingestion on your iPhone to quick log it here.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    } else {
      Label("Open FreakLog on Your iPhone", systemImage: "iphone")
        .font(.headline)
    }
  }
}

// MARK: - SuggestionRow

private struct SuggestionRow: View {
  let suggestion: WatchSuggestion

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(suggestion.swiftUIColor)
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 2) {
        Text(suggestion.title)
          .font(.headline)
          .lineLimit(2)
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }

  // "Oral · 100 mg", with the latest dose, or the substances of a formulation
  private var subtitle: String {
    if let formulation = suggestion.formulation {
      return formulation.components.map(\.displayName).joined(separator: ", ")
    }
    guard let latest = suggestion.doses.first else { return suggestion.routeName }
    return "\(suggestion.routeName) · \(suggestion.description(of: latest))"
  }
}
