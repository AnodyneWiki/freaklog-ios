import XCTest
@testable import FreakLog

// MARK: - AssistantConversationTests

@MainActor
final class AssistantConversationTests: XCTestCase {
  func testToolResultsGoBackUntilTheModelAnswers() async throws {
    let client = ScriptedClient(replies: [
      .success([.completed(AssistantReply(
        text: "",
        toolCalls: [AssistantToolCall(id: "1", name: "list_recent_experiences", arguments: [:])]))]),
      .success([.text("You had "), .text("none."), .completed(AssistantReply(text: "You had none."))]),
    ])
    let conversation = APIConversation(client: client, model: "m", system: "s", toolbox: makeToolbox(), maxOutputTokens: nil)
    var events: [String] = []
    for try await event in conversation.send("Recent?") {
      switch event {
      case .text(let text, _): events.append("text:\(text)")
      case .toolStarted(let call): events.append("start:\(call.name)")
      case .completed(let text): events.append("completed:\(text)")
      }
    }
    XCTAssertEqual(
      events,
      ["start:list_recent_experiences", "text:You had ", "text:none.", "completed:You had none."])
    XCTAssertEqual(conversation.history.count, 4)
    XCTAssertEqual(client.requests.last?.messages.count, 3)
    guard case .toolResults(let results) = conversation.history[2] else { return XCTFail("No tool results") }
    XCTAssertEqual(results.first?.callID, "1")
    XCTAssertEqual(results.first?.result["status"], "success")
  }

  func testSwitchingModelsKeepsHistoryAndUsesTheNewModelOnTheNextRequest() async throws {
    let replies = Array(repeating: ScriptedClient.Reply.success([.completed(AssistantReply(text: "Answer"))]), count: 2)
    let client = ScriptedClient(replies: replies)
    let conversation = APIConversation(client: client, model: "first", system: "s", toolbox: makeToolbox(), maxOutputTokens: nil)
    for try await _ in conversation.send("First question") {}
    conversation.switchModel(to: "second")
    for try await _ in conversation.send("Follow-up") {}
    XCTAssertEqual(client.requests.map(\.model), ["first", "second"])
    XCTAssertEqual(client.requests.last?.messages, [.user("First question"), .assistant(AssistantReply(text: "Answer")), .user("Follow-up")])
  }

  func testAFailedTurnKeepsItsTextAndCanBeRetried() async throws {
    let client = ScriptedClient(replies: [.failure(AssistantError("Gone"), afterText: "Half an answer")])
    let conversation = APIConversation(client: client, model: "m", system: "s", toolbox: makeToolbox(), maxOutputTokens: nil)
    do {
      for try await _ in conversation.send("Question") { }
      XCTFail("The turn should fail")
    } catch { }
    XCTAssertEqual(conversation.history, [.user("Question"), .assistant(AssistantReply(text: "Half an answer"))])
    XCTAssertEqual(conversation.rollBackLastTurn(), "Question")
    XCTAssertEqual(conversation.history, [])
  }

  func testAFailedTurnWithoutTextIsRemoved() async throws {
    let client = ScriptedClient(replies: [.failure(AssistantError("Gone"), afterText: "")])
    let conversation = APIConversation(client: client, model: "m", system: "s", toolbox: makeToolbox(), maxOutputTokens: nil)
    do {
      for try await _ in conversation.send("Question") { }
    } catch { }
    XCTAssertEqual(conversation.history, [])
    XCTAssertNil(conversation.rollBackLastTurn())
  }

  func testInstructionsIncludeTheExperience() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let experience = Experience.create(at: .now, title: "Saturday", in: context)
    let toolbox = AssistantToolbox(context: context, includesAnodyneWiki: false)
    let instructions = AssistantInstructions.text(for: experience, toolbox: toolbox)
    XCTAssertTrue(instructions.contains("\"title\":\"Saturday\""))
    XCTAssertTrue(instructions.contains("\"experience_id\":\"e1\""))
  }

  func testWebAccessInstructionsReflectWhatTheChatCanDo() {
    let toolbox = makeToolbox()
    let disabled = AssistantInstructions.text(for: nil, toolbox: toolbox)
    XCTAssertTrue(disabled.contains("Web Access is off"))
    XCTAssertFalse(disabled.contains("lookup_anodyne_wiki"))

    let anodyneOnly = AssistantToolbox(
      context: toolbox.context, includesAnodyneWiki: true, includesWebAccess: false)
    let anodyneInstructions = AssistantInstructions.text(for: nil, toolbox: anodyneOnly)
    XCTAssertTrue(anodyneInstructions.contains("check AnodyneWiki first"))
    XCTAssertTrue(anodyneInstructions.contains("user annotations (user_notes"))
    XCTAssertTrue(anodyneInstructions.contains("When asked about subjective effects"))
    XCTAssertTrue(anodyneInstructions.contains("Web Access is off"))

    let searchable = AssistantToolbox(
      context: toolbox.context, includesAnodyneWiki: true, includesWebAccess: true)
    let enabled = AssistantInstructions.text(for: nil, toolbox: searchable)
    XCTAssertTrue(enabled.contains("check AnodyneWiki first"))
    XCTAssertTrue(enabled.contains("the app's data and AnodyneWiki are missing or incomplete"))
    XCTAssertTrue(enabled.contains("Use lookup_wikipedia first as your primary web source"))
    XCTAssertTrue(enabled.contains("Use search_web only as a fallback"))
    XCTAssertTrue(enabled.contains("not a general-purpose chatbot"))
  }

  func testSettingsChangeKeepsChatUntilRestart() throws {
    let defaults = UserDefaults.standard
    let profilesKey = PersistenceController.assistantProfilesKey
    let profileIDKey = PersistenceController.assistantActiveProfileKey
    let webKey = PersistenceController.isAssistantWebAccessEnabledKey
    let saved = [profilesKey, profileIDKey, webKey].map { ($0, defaults.object(forKey: $0)) }
    defer {
      for (key, value) in saved {
        defaults.set(value, forKey: key)
      }
    }

    var profile = AssistantProfile(preset: .ollama)
    profile.baseURL = "http://127.0.0.1:1/v1"
    profile.model = "test-model"
    defaults.set(try JSONEncoder().encode([profile]), forKey: profilesKey)
    defaults.set(profile.id.uuidString, forKey: profileIDKey)
    defaults.set(false, forKey: webKey)

    let chat = AssistantChat(experience: nil)
    defer { chat.cancel() }
    chat.startIfNeeded()
    chat.send("What did I log today?")
    XCTAssertTrue(chat.hasQuestions)
    let transcript = chat.items

    defaults.set(true, forKey: webKey)
    chat.startIfNeeded()
    XCTAssertTrue(chat.requiresRestart)
    XCTAssertEqual(chat.items, transcript)

    defaults.set(false, forKey: webKey)
    chat.startIfNeeded()
    XCTAssertFalse(chat.requiresRestart)
    XCTAssertEqual(chat.items, transcript)

    defaults.set(true, forKey: webKey)
    chat.startIfNeeded()
    chat.start()
    XCTAssertFalse(chat.requiresRestart)
    XCTAssertTrue(chat.items.isEmpty)
  }

  private func makeToolbox() -> AssistantToolbox {
    AssistantToolbox(context: PersistenceController(inMemory: true).viewContext, includesAnodyneWiki: false)
  }
}

// MARK: - ScriptedClient

// Answers each request with the next scripted reply
private final class ScriptedClient: AssistantChatClient, @unchecked Sendable {
  init(replies: [Reply]) {
    self.replies = replies
  }

  enum Reply {
    case success([AssistantStreamEvent])
    case failure(AssistantError, afterText: String)
  }

  var requests: [AssistantRequest] {
    lock.withLock { sentRequests }
  }

  func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
    let reply = lock.withLock {
      sentRequests.append(request)
      return replies.removeFirst()
    }
    return AsyncThrowingStream { continuation in
      switch reply {
      case .success(let events):
        events.forEach { continuation.yield($0) }
        continuation.finish()
      case .failure(let error, let text):
        if !text.isEmpty {
          continuation.yield(.text(text))
        }
        continuation.finish(throwing: error)
      }
    }
  }

  func models() async throws -> [String] { [] }

  private let lock = NSLock()
  private var replies: [Reply]
  private var sentRequests: [AssistantRequest] = []

}
