import CoreData
import Foundation

// MARK: - AssistantChatItem

// One entry of the transcript
enum AssistantChatItem: Identifiable, Equatable {
  case message(Message)
  // A line about the chat itself, e.g. that it continues with another model
  case notice(Notice)

  struct Notice: Equatable {
    let id = UUID()
    let text: String
  }

  struct Message: Equatable {
    enum State: Equatable {
      // Waiting for the first text
      case waiting
      case streaming
      case done
      // The user stopped the answer before it was finished
      case stopped
      case failed
    }

    let id = UUID()
    let isUser: Bool
    var text: String
    var state: State = .done
  }

  var id: UUID {
    switch self {
    case .message(let message): message.id
    case .notice(let notice): notice.id
    }
  }

  var message: Message? {
    if case .message(let message) = self { message } else { nil }
  }
}

// MARK: - AssistantChat

// A chat with the assistant, about one experience or the whole journal. Nothing of it is saved: it ends with
// the screen, also when the app locks.
@MainActor
final class AssistantChat: ObservableObject {
  init(experience: Experience?, initialPrompt: String? = nil) {
    self.experience = experience
    pendingPrompt = initialPrompt
  }

  enum Phase: Equatable {
    case ready
    // Something has to be set up in the assistant settings first
    case needsSetup(String)
  }

  static let experienceSuggestions = [
    "Summarize this session",
    "Is anything I took still active?",
    "Were there risky combinations in this session?",
    "When did I last take these substances before?",
  ]
  static let journalSuggestions = [
    "What is still active from today?",
    "What did I take in the past 30 days?",
    "What have I used most this year?",
    "Find my favorite past experiences",
  ]
  static let summaryPrompt = experienceSuggestions[0]

  @Published private(set) var phase = Phase.ready
  @Published private(set) var items: [AssistantChatItem] = []
  @Published private(set) var isBusy = false
  // What the assistant is doing, e.g. "Looking through your journal…"
  @Published private(set) var status: String?
  // The last question can be sent again: it was answered, failed or stopped
  @Published private(set) var canRetry = false
  @Published private(set) var profiles: [AssistantProfile] = []
  @Published private(set) var activeProfile: AssistantProfile?
  // The models the active provider offers, loaded when the chat starts
  @Published private(set) var models: [String] = []
  @Published private(set) var isLoadingModels = false
  // Answers that were added to the experience's notes
  @Published private(set) var addedToNotes: Set<UUID> = []

  let experience: Experience?

  var suggestions: [String] {
    experience == nil ? Self.journalSuggestions : Self.experienceSuggestions
  }

  var hasQuestions: Bool {
    items.contains { $0.message?.isUser == true }
  }

  // What the assistant knows about without looking it up
  var contextLabel: String {
    guard let experience else { return "About your whole journal" }
    let title = experience.titleUnwrapped
    return title.isEmpty ? "About this experience" : "About “\(title)”"
  }

  // What keeps the profile from being used, nil when nothing does
  static func setupProblem(of profile: AssistantProfile) -> String? {
    if profile.standard == .onDevice {
      return OnDeviceModel.unavailableReason
    }
    if profile.baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
      return "Enter the server address of “\(profile.name)”."
    }
    if profile.model.trimmingCharacters(in: .whitespaces).isEmpty {
      return "Choose a model for “\(profile.name)”."
    }
    if profile.preset.needsAPIKey, !AssistantKeychain.hasKey(for: profile.id) {
      return "“\(profile.name)” has no API key."
    }
    return nil
  }

  // Starts the chat when it opens or when its provider or tools change in settings.
  func startIfNeeded() {
    guard hasStarted else {
      start()
      return
    }
    profiles = AssistantProfileStore.profiles
    if phase != .ready || AssistantProfileStore.activeProfile != activeProfile ||
      allowsWikiLookups != AssistantProfileStore.isAnodyneWikiEnabled ||
      allowsWebSearch != AssistantWebSearch.isEnabled ||
      activeProfile.map({ AssistantKeychain.key(for: $0.id) }) != activeKey {
      start()
    }
  }

  func start() {
    hasStarted = true
    turnTask?.cancel()
    turnTask = nil
    chatID = UUID()
    conversation = nil
    items = []
    addedToNotes = []
    isBusy = false
    status = nil
    canRetry = false
    profiles = AssistantProfileStore.profiles
    activeProfile = AssistantProfileStore.activeProfile
    activeKey = activeProfile.map { AssistantKeychain.key(for: $0.id) }
    allowsWikiLookups = AssistantProfileStore.isAnodyneWikiEnabled
    allowsWebSearch = AssistantWebSearch.isEnabled
    loadModels()
    guard let profile = activeProfile else {
      phase = .needsSetup("Add a provider to start chatting.")
      return
    }
    if let problem = Self.setupProblem(of: profile) {
      phase = .needsSetup(problem)
      return
    }
    let limits: AssistantToolbox.Limits = profile.standard == .onDevice ? .compact : .standard
    let webSearch = allowsWebSearch ? AssistantWebSearch(profile: profile, apiKey: activeKey ?? "") : nil
    let toolbox = AssistantToolbox(
      context: PersistenceController.shared.viewContext,
      limits: limits,
      includesAnodyneWiki: allowsWikiLookups,
      webSearch: webSearch?.tool(textLimit: limits.maxTextCharacters) { [weak self] in
        self?.activeProfile?.model ?? profile.model
      })
    let instructions = AssistantInstructions.text(for: experience, toolbox: toolbox)
    if profile.standard == .onDevice {
      conversation = OnDeviceModel.conversation(instructions: instructions, toolbox: toolbox)
    } else if let client = profile.client(apiKey: activeKey ?? "") {
      conversation = APIConversation(
        client: client,
        model: profile.model,
        system: instructions,
        toolbox: toolbox,
        maxOutputTokens: profile.maxOutputTokens)
    }
    guard conversation != nil else {
      phase = .needsSetup("This provider can't be used on this device.")
      return
    }
    self.toolbox = toolbox
    phase = .ready
    if let prompt = pendingPrompt {
      pendingPrompt = nil
      send(prompt)
    }
  }

  func switchProfile(to id: UUID) {
    guard !isBusy, profiles.contains(where: { $0.id == id }) else { return }
    AssistantProfileStore.setActive(id)
    start()
  }

  func selectModel(_ model: String) {
    guard !isBusy, var profile = activeProfile, model != profile.model else { return }
    profile.choose(model: model)
    AssistantProfileStore.save(profile)
    guard let conversation = conversation as? APIConversation else {
      start()
      return
    }
    conversation.switchModel(to: model)
    profiles = AssistantProfileStore.profiles
    activeProfile = profile
    if hasQuestions {
      items.append(.notice(.init(text: "Continuing with \(model)")))
    }
  }

  func loadModels() {
    modelListTask?.cancel()
    models = []
    isLoadingModels = false
    guard let profile = activeProfile, profile.standard != .onDevice,
          let client = profile.client(apiKey: activeKey ?? "") else { return }
    isLoadingModels = true
    modelListTask = Task { [weak self] in
      let loaded = (try? await client.models()) ?? []
      guard !Task.isCancelled else { return }
      self?.models = loaded.uniqued()
      self?.isLoadingModels = false
    }
  }

  private var modelListTask: Task<Void, Never>?

  func send(_ text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isBusy, let conversation, let toolbox else { return }
    let reply = AssistantChatItem.Message(isUser: false, text: "", state: .waiting)
    items.append(.message(.init(isUser: true, text: text)))
    items.append(.message(reply))
    isBusy = true
    canRetry = false
    status = "Thinking…"
    let chatID = chatID
    var turn = Turn(replyID: reply.id)
    turnTask = Task { [weak self] in
      do {
        for try await event in conversation.send(text) {
          guard let self, self.chatID == chatID, !Task.isCancelled else { return }
          handle(event, in: &turn, toolbox: toolbox)
        }
      } catch {
        guard let self, self.chatID == chatID, !Task.isCancelled else { return }
        fail(turn: &turn, with: error)
      }
    }
  }

  // Stops the answer that is streaming; what arrived of it stays
  func stop() {
    guard let task = turnTask, let conversation else { return }
    turnTask = nil
    task.cancel()
    let chatID = chatID
    Task {
      // The conversation repairs its history when the turn ends, so the next question waits for that
      await task.value
      await conversation.waitForTurnToFinish()
      guard self.chatID == chatID else { return }
      items = items.map { item in
        switch item {
        case .message(var message) where message.state == .waiting || message.state == .streaming:
          message.state = .stopped
          return .message(message)
        default:
          return item
        }
      }
      isBusy = false
      status = nil
      canRetry = true
    }
  }

  // Sends the last question again, in place of the answer it got
  func retry() {
    guard
      !isBusy, let conversation,
      let index = items.lastIndex(where: { $0.message?.isUser == true }),
      let question = conversation.rollBackLastTurn() ?? items[index].message?.text
    else { return }
    items.removeSubrange(index...)
    send(question)
  }

  // Adds an answer to the end of the experience's notes
  func addToNotes(_ message: AssistantChatItem.Message) throws {
    guard let experience, let context = experience.managedObjectContext, !addedToNotes.contains(message.id) else { return }
    let previousNotes = experience.text
    let notes = experience.textUnwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
    let addition = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    experience.text = notes.isEmpty ? addition : notes + "\n\n" + addition
    do {
      try context.save()
      addedToNotes.insert(message.id)
    } catch {
      experience.text = previousNotes
      throw error
    }
  }

  func cancel() {
    modelListTask?.cancel()
    turnTask?.cancel()
    turnTask = nil
    chatID = UUID()
    status = nil
  }

  // The state of the turn that is streaming. Text before a tool call stays in its own message; the answer after
  // the tools streams into a new one.
  private struct Turn {
    var replyID: UUID
    var text = ""
    var lastDraw = Date.distantPast
  }

  // How often streaming text is drawn at most
  private static let drawInterval: TimeInterval = 0.05

  private var pendingPrompt: String?
  private var conversation: (any AssistantConversation)?
  private var toolbox: AssistantToolbox?
  private var turnTask: Task<Void, Never>?
  // Changes with every new chat, so a turn that was still running can't change the new one
  private var chatID = UUID()

  private var allowsWikiLookups = false
  private var allowsWebSearch = false
  private var activeKey: String?
  private var hasStarted = false

  private func handle(_ event: AssistantTurnEvent, in turn: inout Turn, toolbox: AssistantToolbox) {
    switch event {
    case .text(let text, let replacesPrevious):
      if replacesPrevious {
        turn.text = text
      } else {
        turn.text += text
      }
      if Date.now.timeIntervalSince(turn.lastDraw) >= Self.drawInterval {
        turn.lastDraw = .now
        updateMessage(turn.replyID) { message in
          message.text = turn.text
          message.state = .streaming
        }
      }
    case .toolStarted(let call):
      if !turn.text.isEmpty {
        updateMessage(turn.replyID) { message in
          message.text = turn.text
          message.state = .done
        }
        let next = AssistantChatItem.Message(isUser: false, text: "", state: .waiting)
        items.append(.message(next))
        turn.replyID = next.id
        turn.text = ""
      }
      status = toolbox.progress(for: call)
    case .completed(let text):
      if !text.isEmpty { turn.text = text }
      if turn.text.isEmpty {
        let questionIndex = items.lastIndex { $0.message?.isUser == true } ?? 0
        let answeredBefore = items[questionIndex...].contains { item in
          guard let message = item.message else { return false }
          return !message.isUser && message.id != turn.replyID && !message.text.isEmpty
        }
        if answeredBefore {
          items.removeAll { $0.id == turn.replyID }
        } else {
          updateMessage(turn.replyID) { message in
            message.text = "The assistant gave an empty answer."
            message.state = .failed
          }
        }
      } else {
        updateMessage(turn.replyID) { message in
          message.text = turn.text
          message.state = .done
        }
      }
      finishTurn()
    }
  }

  private func fail(turn: inout Turn, with error: Error) {
    let message = (error as? AssistantError)?.message ?? error.localizedDescription
    if turn.text.isEmpty || (error as? AssistantError)?.discardsPartialText == true {
      updateMessage(turn.replyID) { reply in
        reply.text = message
        reply.state = .failed
      }
    } else {
      updateMessage(turn.replyID) { reply in
        reply.text = turn.text
        reply.state = .done
      }
      items.append(.message(.init(isUser: false, text: message, state: .failed)))
    }
    finishTurn()
  }

  private func finishTurn() {
    turnTask = nil
    isBusy = false
    status = nil
    canRetry = true
  }

  private func updateMessage(_ id: UUID, _ change: (inout AssistantChatItem.Message) -> Void) {
    guard let index = items.firstIndex(where: { $0.id == id }), case .message(var message) = items[index] else { return }
    change(&message)
    items[index] = .message(message)
  }
}
