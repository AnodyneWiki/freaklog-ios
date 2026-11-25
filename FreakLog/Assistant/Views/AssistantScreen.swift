import SwiftUI

private struct AssistantTranscriptFrame: PreferenceKey {
  static let defaultValue: CGRect? = nil

  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}

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
            confirmsNewChat = true
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
      .onChange(of: path.isEmpty) { isAtChat in
        if isAtChat { chat.startIfNeeded() }
      }
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
            followsLatest = true
            chat.switchProfile(to: profile.id)
          }
        }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("Switching providers starts a new conversation.")
      }
      .confirmationDialog("Start a new chat?", isPresented: $confirmsNewChat, titleVisibility: .visible) {
        Button("Start New Chat", role: .destructive) {
          draft = ""
          followsLatest = true
          chat.start()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Starting a new chat replaces this conversation and applies your current Assistant settings.")
      }
    }
    .onChange(of: isAssistantEnabled) { enabled in
      if !enabled { dismiss() }
    }
    .sheet(isPresented: $showsWebSearch) { AssistantWebSearchScreen() }
    .onDisappear { chat.cancel() }
  }

  @AppStorage(PersistenceController.isAssistantEnabledKey) private var isAssistantEnabled = false
  @AppStorage(PersistenceController.isAssistantWebAccessEnabledKey) private var isWebAccessEnabled = false
  @StateObject private var chat: AssistantChat
  @Environment(\.dismiss) private var dismiss
  @State private var noteSaveError: String?
  @State private var draft = ""
  @State private var showsWebSearch = false
  @State private var confirmsNewChat = false
  @State private var profileToSwitchTo: AssistantProfile?
  @State private var path = NavigationPath()
  @State private var followsLatest = true
  @State private var transcriptTop: CGFloat?
  @GestureState private var isDraggingTranscript = false
  @FocusState private var isInputFocused: Bool

  private let bottomID = "bottom"
  private let transcriptSpace = "assistantTranscript"
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
    .disabled(chat.requiresRestart)
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      GeometryReader { viewport in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            if let contextLabel = chat.contextLabel {
              Text(contextLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
            }
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
          .background {
            GeometryReader { content in
              Color.clear.preference(
                key: AssistantTranscriptFrame.self,
                value: content.frame(in: .named(transcriptSpace)))
            }
          }
        }
        .coordinateSpace(name: transcriptSpace)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
          DragGesture().updating($isDraggingTranscript) { _, dragging, _ in dragging = true }
        )
        .onPreferenceChange(AssistantTranscriptFrame.self) { frame in
          guard let frame, frame.minY != transcriptTop else { return }
          // Streaming changes the content height even when the reader's position hasn't moved.
          if transcriptTop != nil {
            followsLatest = frame.maxY - viewport.size.height <= 64
          }
          transcriptTop = frame.minY
        }
        .onChange(of: chat.items) { _ in
          if followsLatest && !isDraggingTranscript {
            proxy.scrollTo(bottomID, anchor: .bottom)
          }
        }
        .overlay(alignment: .bottom) {
          if chat.hasQuestions && !followsLatest {
            Button {
              followsLatest = true
              proxy.scrollTo(bottomID, anchor: .bottom)
            } label: {
              Label("Jump to Latest", systemImage: "arrow.down")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
            }
            .padding(.bottom, 8)
          }
        }
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
          followsLatest = true
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
      if isWebAccessEnabled {
        webSearchButton.frame(maxWidth: .infinity, alignment: .leading)
      }
      if chat.requiresRestart {
        VStack(alignment: .leading, spacing: 4) {
          Text("Assistant settings changed. Start a new chat to use them.")
            .foregroundStyle(.secondary)
          Button("Start New Chat") { confirmsNewChat = true }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask the assistant", text: $draft, axis: .vertical)
          .lineLimit(1 ... 6)
          .focused($isInputFocused)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .frame(minHeight: 44)
          .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
          .disabled(chat.requiresRestart)
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
            followsLatest = true
            chat.send(draft)
            draft = ""
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title)
              .assistantTapTarget()
          }
          .disabled(chat.requiresRestart || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

  private var webSearchButton: some View {
    Button {
      showsWebSearch = true
    } label: {
      Label("Search the Web", systemImage: "globe")
        .font(.subheadline)
        .assistantTapTarget()
    }
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
      if isWebAccessEnabled { webSearchButton }
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
      canRetry: isLast && chat.canRetry && !chat.isBusy && !chat.requiresRestart,
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

private struct AssistantWebSearchScreen: View {
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var submittedQuery: String?
  @State private var results: [AssistantWebSearch.SearchResult] = []
  @State private var error: String?
  @State private var searchTask: Task<Void, Never>?
  @State private var isSearching = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Search query", text: $query)
            .submitLabel(.search)
            .onSubmit(search)
            .disabled(isSearching)
          Button("Search", action: search)
            .disabled(!canSearch)
        } footer: {
          Text("Search queries are sent to Exa. Leave out personal details.")
        }

        if isSearching {
          ProgressView("Searching…")
        } else if let error {
          Section {
            Text(error).foregroundStyle(.secondary)
            Button("Try Again") {
              if let submittedQuery { runSearch(submittedQuery) }
            }
          }
        } else if submittedQuery != nil {
          Section("Results") {
            if results.isEmpty {
              Text("No results found.").foregroundStyle(.secondary)
            }
            ForEach(results.indices, id: \.self) { index in
              let result = results[index]
              if let url = result.url {
                Link(destination: url) { resultLabel(result) }
              } else {
                resultLabel(result)
              }
            }
          }
        }
      }
      .navigationTitle("Search the Web")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .onDisappear { searchTask?.cancel() }
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSearch: Bool { !isSearching && !trimmedQuery.isEmpty }

  private func search() {
    guard canSearch else { return }
    runSearch(trimmedQuery)
  }

  private func runSearch(_ submitted: String) {
    submittedQuery = submitted
    isSearching = true
    error = nil
    results = []
    searchTask = Task {
      defer { isSearching = false }
      do {
        let response = try await AssistantWebSearch.search(query: submitted, textLimit: 800)
        try Task.checkCancellation()
        results = AssistantWebSearch.searchResults(from: response)
      } catch {
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }

  private func resultLabel(_ result: AssistantWebSearch.SearchResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(result.title).font(.headline)
      if let host = result.url?.host {
        Text(host).font(.caption).foregroundStyle(.secondary)
      }
      if !result.snippet.isEmpty {
        Text(result.snippet).font(.subheadline).foregroundStyle(.primary)
      }
    }
    .padding(.vertical, 3)
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
