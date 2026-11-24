import SwiftUI

// MARK: - AssistantScreen

// The chat with the assistant, about an experience or the whole journal. Opened with a prompt, such as the
// summary of a session, it asks that right away.
struct AssistantScreen: View {
  init(experience: Experience?, initialPrompt: String? = nil, suggestsCurrentSessionSummary: Bool = false) {
    _chat = StateObject(wrappedValue: AssistantChat(experience: experience, initialPrompt: initialPrompt))
    self.suggestsCurrentSessionSummary = suggestsCurrentSessionSummary
  }

  var body: some View {
    NavigationStack(path: $path) {
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
          modelMenu
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .assistantTapTarget()
          }
          .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            draft = ""
            chat.start()
          } label: {
            Image(systemName: "square.and.pencil")
              .assistantTapTarget()
          }
          .accessibilityLabel("New Chat")
          .disabled(!chat.hasQuestions)
        }
      }
      .navigationDestination(for: GlobalNavigationDestination.self) { destination in
        getScreen(from: destination)
      }
      .onAppear { chat.startIfNeeded() }
      .alert("Couldn’t Add to Notes", isPresented: Binding(get: { noteSaveError != nil }, set: { if !$0 { noteSaveError = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(noteSaveError ?? "")
      }
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
        Text("Switching providers starts a new conversation.")
      }
    }
    .onChange(of: isAssistantEnabled) { enabled in
      if !enabled { dismiss() }
    }
    .onDisappear { chat.cancel() }
  }

  @AppStorage(PersistenceController.isAssistantEnabledKey) private var isAssistantEnabled = false
  @StateObject private var chat: AssistantChat
  @Environment(\.dismiss) private var dismiss
  @State private var noteSaveError: String?
  @State private var draft = ""
  @State private var profileToSwitchTo: AssistantProfile?
  @State private var path = NavigationPath()
  @FocusState private var isInputFocused: Bool

  private let bottomID = "bottom"
  private let suggestsCurrentSessionSummary: Bool

  // The title: the model in use, which opens a menu of models and providers
  private var modelMenu: some View {
    Menu {
      if let profile = chat.activeProfile, profile.standard != .onDevice {
        Section(profile.name) {
          ForEach(profile.quickModels, id: \.self) { model in
            modelButton(model, isSelected: model == profile.model)
          }
          if !chat.models.isEmpty {
            Menu {
              ForEach(chat.models, id: \.self) { model in
                modelButton(model, isSelected: model == profile.model)
              }
            } label: {
              Label("All Models", systemImage: "list.bullet")
            }
          } else if chat.isLoadingModels {
            Text("Loading Models…")
          } else {
            Button("Fetch Models", action: chat.loadModels)
          }
        }
      }
      let otherProfiles = chat.profiles.filter { $0.id != chat.activeProfile?.id }
      if !otherProfiles.isEmpty {
        Section("Providers") {
          ForEach(otherProfiles) { profile in
            Button {
              if chat.hasQuestions {
                profileToSwitchTo = profile
              } else {
                chat.switchProfile(to: profile.id)
              }
            } label: {
              Text("\(profile.name) · \(profile.modelName)")
            }
          }
        }
      }
      Button {
        path.append(GlobalNavigationDestination.assistantSettings)
      } label: {
        Label("Assistant Settings", systemImage: "gearshape")
      }
    } label: {
      VStack(spacing: 1) {
        HStack(spacing: 4) {
          Text(chat.activeProfile.flatMap { $0.modelName.isEmpty ? nil : $0.modelName } ?? "Assistant")
            .font(.headline)
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.bold))
            .foregroundColor(.secondary)
        }
        if let profile = chat.activeProfile, profile.standard != .onDevice {
          Text(profile.name)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: 200)
      .assistantTapTarget()
      .accessibilityElement(children: .combine)
      .accessibilityHint("Opens model and provider options")
    }
    .disabled(chat.isBusy)
  }

  private func modelButton(_ model: String, isSelected: Bool) -> some View {
    Button {
      chat.selectModel(model)
    } label: {
      if isSelected {
        Label(model, systemImage: "checkmark")
      } else {
        Text(model)
      }
    }
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          Text(chat.contextLabel)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
          ForEach(chat.items) { item in
            switch item {
            case .message(let message):
              MessageView(
                message: message,
                status: chat.status,
                actions: actions(for: message))
            case .notice(let notice):
              Text(notice.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
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
    let prompts = suggestsCurrentSessionSummary ? ["Summarize current session"] + chat.suggestions : chat.suggestions
    return VStack(alignment: .leading, spacing: 8) {
      ForEach(prompts, id: \.self) { suggestion in
        Button {
          chat.send(suggestion)
        } label: {
          Text(suggestion)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .assistantTapTarget()
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
          .frame(minHeight: 44)
          .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        if chat.isBusy {
          Button {
            chat.stop()
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.title)
              .assistantTapTarget()
          }
          .accessibilityLabel("Stop")
        } else {
          Button {
            chat.send(draft)
            draft = ""
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title)
              .assistantTapTarget()
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
      Image(systemName: "text.bubble")
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
      !message.isUser, [.done, .stopped, .failed].contains(message.state)
    else { return nil }
    let isLast = chat.items.last { $0.message?.isUser == false }?.id == message.id
    return MessageView.Actions(
      canAddToNotes: chat.experience != nil && !chat.isBusy,
      isAddedToNotes: chat.addedToNotes.contains(message.id),
      canRetry: isLast && chat.canRetry && !chat.isBusy,
      addToNotes: {
        do {
          try chat.addToNotes(message)
        } catch {
          noteSaveError = error.localizedDescription
        }
      },
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
  // What the assistant is doing, shown while waiting for its answer
  let status: String?
  let actions: Actions?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
          HStack(spacing: 8) {
            ProgressView()
            if let status {
              Text(status)
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
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
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(spacing: 16))
    return layout {
      if hasText {
        Button {
          UIPasteboard.general.string = message.text
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
            .assistantTapTarget()
        }
      }
      if hasText, actions.canAddToNotes || actions.isAddedToNotes {
        Button(action: actions.addToNotes) {
          if actions.isAddedToNotes {
            Label("Added to Notes", systemImage: "checkmark")
              .assistantTapTarget()
          } else {
            Label("Add to Notes", systemImage: "note.text.badge.plus")
              .assistantTapTarget()
          }
        }
        .disabled(actions.isAddedToNotes)
      }
      if actions.canRetry {
        Button(action: actions.retry) {
          Label("Retry", systemImage: "arrow.clockwise")
            .assistantTapTarget()
        }
      }
    }
    .font(.footnote)
    .buttonStyle(.borderless)
  }
}

private extension View {
  func assistantTapTarget() -> some View {
    frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
  }
}
