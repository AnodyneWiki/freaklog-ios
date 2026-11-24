import CoreData
import Foundation

// MARK: - AssistantChatItem

// One entry of the transcript
enum AssistantChatItem: Identifiable, Equatable {
  case message(Message)
  case tool(ToolEvent)

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

  // A tool the assistant ran, shown as a line between the messages
  struct ToolEvent: Equatable {
    enum Status: Equatable {
      case running
      case succeeded
      case failed
    }

    let id = UUID()
    let label: String
    var status: Status = .running
    var summary: String?
  }

  var id: UUID {
    switch self {
    case .message(let message): message.id
    case .tool(let tool): tool.id
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
    guard let experience else { return "Whole journal" }
    let title = experience.titleUnwrapped
    return title.isEmpty ? "This experience" : "This experience: \(title)"
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

  // Starts the chat the first time, and again when the providers changed before anything was asked, e.g. after
  // adding one from the setup message
  func startIfNeeded() {
    guard hasStarted else {
      start()
      return
    }
    guard !hasQuestions else { return }
    if phase != .ready || AssistantProfileStore.profiles != profiles || AssistantProfileStore.activeProfile != activeProfile {
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
    isBusy = false
    status = nil
    canRetry = false
    profiles = AssistantProfileStore.profiles
    activeProfile = AssistantProfileStore.activeProfile
    guard let profile = activeProfile else {
      phase = .needsSetup("Add a provider to start chatting.")
      return
    }
    if let problem = Self.setupProblem(of: profile) {
      phase = .needsSetup(problem)
      return
    }
    let toolbox = AssistantToolbox(
      context: PersistenceController.shared.viewContext,
      limits: profile.standard == .onDevice ? .compact : .standard,
      includesAnodyneWiki: AssistantProfileStore.isAnodyneWikiEnabled)
    let instructions = AssistantInstructions.text(for: experience, toolbox: toolbox)
    if profile.standard == .onDevice {
      conversation = OnDeviceModel.conversation(instructions: instructions, toolbox: toolbox)
    } else if let client = profile.client(apiKey: AssistantKeychain.key(for: profile.id)) {
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
    items = [.message(.init(
      isUser: false,
      text: "Hi! I can look through your journal, sum up sessions and answer questions about substances and safer use. Ask me anything or pick a suggestion."))]
    if let prompt = pendingPrompt {
      pendingPrompt = nil
      send(prompt)
    }
  }

  func switchProfile(to id: UUID) {
    AssistantProfileStore.setActive(id)
    start()
  }

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
          guard let self, self.chatID == chatID else { return }
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
    guard let task = turnTask else { return }
    turnTask = nil
    task.cancel()
    let chatID = chatID
    Task {
      // The conversation repairs its history when the turn ends, so the next question waits for that
      await task.value
      guard self.chatID == chatID else { return }
      items = items.map { item in
        switch item {
        case .message(var message) where message.state == .waiting || message.state == .streaming:
          message.state = .stopped
          return .message(message)
        case .tool(var tool) where tool.status == .running:
          tool.status = .failed
          tool.summary = "stopped"
          return .tool(tool)
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
  func addToNotes(_ message: AssistantChatItem.Message) {
    guard let experience else { return }
    let notes = experience.textUnwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
    let addition = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    experience.text = notes.isEmpty ? addition : notes + "\n\n" + addition
    do {
      try PersistenceController.shared.viewContext.save()
      addedToNotes.insert(message.id)
    } catch {
      print("Failed to add the answer to the notes: \(error)")
    }
  }

  func cancel() {
    turnTask?.cancel()
    turnTask = nil
    chatID = UUID()
  }

  // The state of the turn that is streaming. Text before a tool call stays in its own message; the answer after
  // the tools streams into a new one.
  private struct Turn {
    var replyID: UUID
    var text = ""
    var lastDraw = Date.distantPast
    var toolItems: [String: UUID] = [:]
  }

  // How often streaming text is drawn at most
  private static let drawInterval: TimeInterval = 0.05

  private var pendingPrompt: String?
  private var conversation: (any AssistantConversation)?
  private var toolbox: AssistantToolbox?
  private var turnTask: Task<Void, Never>?
  // Changes with every new chat, so a turn that was still running can't change the new one
  private var chatID = UUID()

  private var hasStarted = false

  private func handle(_ event: AssistantTurnEvent, in turn: inout Turn, toolbox: AssistantToolbox) {
    switch event {
    case .text(let delta):
      turn.text += delta
      if Date.now.timeIntervalSince(turn.lastDraw) >= Self.drawInterval {
        turn.lastDraw = .now
        updateMessage(turn.replyID) { message in
          message.text = turn.text
          message.state = .streaming
        }
        status = "Writing…"
      }
    case .toolStarted(let key, let call):
      let tool = AssistantChatItem.ToolEvent(label: toolbox.label(for: call))
      turn.toolItems[key] = tool.id
      if turn.text.isEmpty {
        if let index = items.firstIndex(where: { $0.id == turn.replyID }) {
          items.insert(.tool(tool), at: index)
        }
      } else {
        updateMessage(turn.replyID) { message in
          message.text = turn.text
          message.state = .done
        }
        let next = AssistantChatItem.Message(isUser: false, text: "", state: .waiting)
        items.append(.tool(tool))
        items.append(.message(next))
        turn.replyID = next.id
        turn.text = ""
      }
      status = toolbox.progress(for: call)
    case .toolFinished(let key, let call, let result):
      if let id = turn.toolItems[key], let index = items.firstIndex(where: { $0.id == id }), case .tool(var tool) = items[index] {
        tool.status = result["status"]?.string == "error" ? .failed : .succeeded
        tool.summary = toolbox.summary(for: call, result: result)
        items[index] = .tool(tool)
      }
      status = "Thinking…"
    case .completed(let text):
      if turn.text.isEmpty {
        turn.text = text
      }
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
    for (index, item) in items.enumerated() {
      if case .tool(var tool) = item, tool.status == .running {
        tool.status = .failed
        items[index] = .tool(tool)
      }
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
