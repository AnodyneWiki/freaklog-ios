import Foundation

// MARK: - AssistantTurnEvent

// What happens during one turn of the user, in order
enum AssistantTurnEvent: Sendable {
  case text(String)
  // `key` is unique within the turn and pairs a tool's start with its finish
  case toolStarted(key: String, call: AssistantToolCall)
  case toolFinished(key: String, call: AssistantToolCall, result: JSONValue)
  // The model answered without asking for more tools
  case completed(String)
}

// MARK: - AssistantConversation

// A chat with one model, which runs the tools the model asks for
@MainActor
protocol AssistantConversation: AnyObject {
  func send(_ text: String) -> AsyncThrowingStream<AssistantTurnEvent, Error>

  // Removes the last question and everything after it, and returns the question so it can be sent again
  func rollBackLastTurn() -> String?
}

// MARK: - APIConversation

// A chat over a provider's API. Each turn streams the model's answer, runs the tools it asks for, sends their
// results back and repeats until the model answers, at most `maxToolRounds` times.
//
// When a turn is stopped or fails, the history is repaired so the next request is still valid: an answer whose
// tool calls got no results is removed, text that arrived is kept as an answer, and a turn that produced
// nothing is removed entirely. The history is only ever added to at its end, which keeps the providers'
// prompt caches and signed thinking blocks valid.
@MainActor
final class APIConversation: AssistantConversation {
  init(client: any AssistantChatClient, model: String, system: String, toolbox: AssistantToolbox, maxOutputTokens: Int?) {
    self.client = client
    self.model = model
    self.system = system
    self.toolbox = toolbox
    self.maxOutputTokens = maxOutputTokens
  }

  static let maxToolRounds = 8
  // Real turns use a handful of tools; a model asking for more is stopped, not served
  static let maxToolCallsPerTurn = 32

  private(set) var history: [AssistantMessage] = []

  func send(_ text: String) -> AsyncThrowingStream<AssistantTurnEvent, Error> {
    AsyncThrowingStream { continuation in
      let previous = runningTurn
      let task = Task { @MainActor in
        // A stopped turn repairs the history when it ends, which the next one has to wait for
        await previous?.value
        do {
          try await runTurn(text) { continuation.yield($0) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      runningTurn = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func rollBackLastTurn() -> String? {
    // A failed turn may already be removed by repair, and rolling back would then remove the question before it
    guard isLastTurnInHistory else { return nil }
    isLastTurnInHistory = false
    guard
      let index = history.lastIndex(where: { if case .user = $0 { true } else { false } }),
      case .user(let text) = history[index]
    else { return nil }
    history.removeSubrange(index...)
    return text
  }

  private let client: any AssistantChatClient
  private let model: String
  private let system: String
  private let toolbox: AssistantToolbox
  private let maxOutputTokens: Int?
  // False once the last question was removed again, so there is nothing to roll back
  private var isLastTurnInHistory = false
  private var runningTurn: Task<Void, Never>?

  private func runTurn(_ text: String, emit: (AssistantTurnEvent) -> Void) async throws {
    let checkpoint = history.count
    history.append(.user(text))
    isLastTurnInHistory = true
    var partial = ""
    var isFinished = false
    var toolCallCount = 0
    defer {
      if !isFinished {
        repair(from: checkpoint, keeping: partial)
      }
    }
    do {
      for round in 0 ... Self.maxToolRounds {
        partial = ""
        var reply: AssistantReply?
        let request = AssistantRequest(
          model: model,
          system: system,
          messages: history,
          tools: toolbox.specs,
          maxOutputTokens: maxOutputTokens)
        for try await event in client.stream(request) {
          switch event {
          case .text(let delta):
            partial += delta
            emit(.text(delta))
          case .completed(let completed):
            reply = completed
          }
        }
        try Task.checkCancellation()
        guard let reply else { throw AssistantError("The answer ended unexpectedly.") }
        if reply.toolCalls.isEmpty {
          isFinished = true
          if !reply.text.isEmpty {
            history.append(.assistant(reply))
          } else if history.count == checkpoint + 1 {
            // Anthropic and Gemini reject an empty answer in later requests. Without tool results the turn holds
            // nothing worth keeping, so it is removed and Retry asks again.
            history.removeLast()
            isLastTurnInHistory = false
          }
          emit(.completed(reply.text))
          return
        }
        history.append(.assistant(reply))
        guard round < Self.maxToolRounds else {
          throw AssistantError("The assistant kept using tools without answering. Try a more specific question.")
        }
        toolCallCount += reply.toolCalls.count
        guard toolCallCount <= Self.maxToolCallsPerTurn else {
          throw AssistantError("The assistant asked for too many tools at once. Try a more specific question.")
        }
        var results: [AssistantToolResult] = []
        for (index, call) in reply.toolCalls.enumerated() {
          let key = "\(round)-\(index)"
          emit(.toolStarted(key: key, call: call))
          let result = await toolbox.run(call)
          try Task.checkCancellation()
          emit(.toolFinished(key: key, call: call, result: result))
          results.append(AssistantToolResult(callID: call.id, name: call.name, result: result))
        }
        // All results of one answer go back in one message
        history.append(.toolResults(results))
        partial = ""
      }
    } catch let error as AssistantError where error.discardsPartialText {
      partial = ""
      throw error
    }
  }

  private func repair(from checkpoint: Int, keeping partialText: String) {
    var text = partialText
    if history.count > checkpoint, case .assistant(let last) = history.last, !last.toolCalls.isEmpty {
      history.removeLast()
      if text.isEmpty {
        text = last.text
      }
    }
    if !text.isEmpty {
      history.append(.assistant(AssistantReply(text: text)))
    } else {
      history.removeSubrange(checkpoint...)
      isLastTurnInHistory = false
    }
  }
}
