import SwiftUI

// MARK: - AssistantScreen

// The chat with the assistant, about an experience or the whole journal. Opened with a prompt, such as the
// summary of a session, it asks that right away.
struct AssistantScreen: View {
  init(experience: Experience?, initialPrompt: String? = nil) {
    _chat = StateObject(wrappedValue: AssistantChat(experience: experience, initialPrompt: initialPrompt))
  }

  var body: some View {
    NavigationStack {
      Group {
        switch chat.phase {
        case .ready:
          transcript
        case .needsSetup(let message):
          setupNeeded(message)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          VStack(spacing: 0) {
            Text("Assistant").font(.headline)
            Text(chat.status ?? chat.contextLabel)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
          .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          menu
        }
      }
      .navigationDestination(for: GlobalNavigationDestination.self) { destination in
        getScreen(from: destination)
      }
      .onAppear { chat.startIfNeeded() }
      .confirmationDialog(
        "Switch to \(profileToSwitchTo?.name ?? "")?",
        isPresented: Binding(get: { profileToSwitchTo != nil }, set: { if !$0 { profileToSwitchTo = nil } }),
        titleVisibility: .visible)
      {
        Button("Switch and Start a New Chat") {
          if let profile = profileToSwitchTo {
            chat.switchProfile(to: profile.id)
          }
        }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("The other provider starts without this chat.")
      }
    }
    .onDisappear { chat.cancel() }
  }

  @StateObject private var chat: AssistantChat
  @Environment(\.dismiss) private var dismiss
  @State private var draft = ""
  @State private var profileToSwitchTo: AssistantProfile?
  @FocusState private var isInputFocused: Bool

  private let bottomID = "bottom"

  private var menu: some View {
    Menu {
      if chat.profiles.count > 1 {
        Section("Provider") {
          ForEach(chat.profiles) { profile in
            Button {
              guard profile.id != chat.activeProfile?.id else { return }
              if chat.hasQuestions {
                profileToSwitchTo = profile
              } else {
                chat.switchProfile(to: profile.id)
              }
            } label: {
              if profile.id == chat.activeProfile?.id {
                Label(profile.name, systemImage: "checkmark")
              } else {
                Text(profile.name)
              }
            }
          }
        }
        .disabled(chat.isBusy)
      }
      Button {
        draft = ""
        chat.start()
      } label: {
        Label("New Chat", systemImage: "square.and.pencil")
      }
      NavigationLink(value: GlobalNavigationDestination.assistantSettings) {
        Label("Assistant Settings", systemImage: "gearshape")
      }
    } label: {
      Label("More", systemImage: "ellipsis.circle")
    }
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(chat.items) { item in
            switch item {
            case .message(let message):
              MessageView(
                message: message,
                actions: actions(for: message))
            case .tool(let tool):
              ToolEventView(tool: tool)
            }
          }
          if !chat.hasQuestions {
            suggestions
          }
          Color.clear.frame(height: 1).id(bottomID)
        }
        .padding()
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: chat.items) { _ in
        proxy.scrollTo(bottomID, anchor: .bottom)
      }
      .safeAreaInset(edge: .bottom) {
        inputBar
      }
    }
  }

  private var suggestions: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(chat.suggestions, id: \.self) { suggestion in
        Button {
          chat.send(suggestion)
        } label: {
          Text(suggestion)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(chat.isBusy)
      }
    }
  }

  private var inputBar: some View {
    VStack(spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask the assistant", text: $draft, axis: .vertical)
          .lineLimit(1 ... 6)
          .focused($isInputFocused)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        if chat.isBusy {
          Button {
            chat.stop()
          } label: {
            Image(systemName: "stop.circle.fill").font(.title)
          }
          .accessibilityLabel("Stop")
        } else {
          Button {
            chat.send(draft)
            draft = ""
          } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title)
          }
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityLabel("Send")
        }
      }
      Text("AI answers can be wrong. They are no medical advice.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
    .padding(.top, 8)
    .padding(.bottom, 4)
    .background(.bar)
  }

  private func setupNeeded(_ message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text(message)
        .multilineTextAlignment(.center)
      NavigationLink(value: GlobalNavigationDestination.assistantSettings) {
        Text("Open Assistant Settings")
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func actions(for message: AssistantChatItem.Message) -> MessageView.Actions? {
    guard
      !message.isUser, [.done, .stopped, .failed].contains(message.state),
      message.id != chat.items.first?.id
    else { return nil }
    let isLast = chat.items.last { $0.message?.isUser == false }?.id == message.id
    return MessageView.Actions(
      canAddToNotes: chat.experience != nil && !chat.isBusy,
      isAddedToNotes: chat.addedToNotes.contains(message.id),
      canRetry: isLast && chat.canRetry && !chat.isBusy,
      addToNotes: { chat.addToNotes(message) },
      retry: { chat.retry() })
  }

}

// MARK: - MessageView

private struct MessageView: View {
  struct Actions {
    let canAddToNotes: Bool
    let isAddedToNotes: Bool
    let canRetry: Bool
    let addToNotes: () -> Void
    let retry: () -> Void
  }

  let message: AssistantChatItem.Message
  let actions: Actions?

  var body: some View {
    if message.isUser {
      HStack {
        Spacer(minLength: 48)
        Text(message.text)
          .textSelection(.enabled)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        switch message.state {
        case .waiting:
          ProgressView()
            .padding(.vertical, 4)
        case .failed:
          Label(message.text, systemImage: "exclamationmark.triangle")
            .foregroundColor(.red)
            .textSelection(.enabled)
        default:
          AssistantMarkdownText(text: message.text)
          if message.state == .stopped {
            Text("Stopped")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        if let actions {
          actionRow(actions)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // An answer, not an error or an answer stopped before any text
  private var hasText: Bool {
    message.state != .failed && !message.text.isEmpty
  }

  private func actionRow(_ actions: Actions) -> some View {
    HStack(spacing: 16) {
      if hasText {
        Button {
          UIPasteboard.general.string = message.text
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
      }
      if hasText, actions.canAddToNotes || actions.isAddedToNotes {
        Button(action: actions.addToNotes) {
          if actions.isAddedToNotes {
            Label("Added to Notes", systemImage: "checkmark")
          } else {
            Label("Add to Notes", systemImage: "note.text.badge.plus")
          }
        }
        .disabled(actions.isAddedToNotes)
      }
      if actions.canRetry {
        Button(action: actions.retry) {
          Label("Retry", systemImage: "arrow.clockwise")
        }
      }
    }
    .font(.footnote)
    .buttonStyle(.borderless)
  }
}

// MARK: - ToolEventView

private struct ToolEventView: View {
  let tool: AssistantChatItem.ToolEvent

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      switch tool.status {
      case .running:
        ProgressView().controlSize(.mini)
      case .succeeded:
        Image(systemName: "checkmark.circle")
      case .failed:
        Image(systemName: "exclamationmark.circle")
      }
      Text(tool.label + (tool.summary.map { " · \($0)" } ?? ""))
        .lineLimit(2)
    }
    .font(.footnote)
    .foregroundColor(.secondary)
    .accessibilityElement(children: .combine)
  }
}
