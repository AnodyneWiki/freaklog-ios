import XCTest
@testable import FreakLog

final class AssistantProviderTests: XCTestCase {
  func testServerSentEventsAreSplitByEmptyLines() {
    var parser = ServerSentEventParser()
    var events: [ServerSentEvent] = []
    for line in [": keep-alive", "event: message_start", "data: {\"a\":", "data: 1}", "", "data: [DONE]"] {
      if let event = parser.feed(line) {
        events.append(event)
      }
    }
    if let event = parser.finish() {
      events.append(event)
    }
    XCTAssertEqual(events, [
      ServerSentEvent(name: "message_start", data: "{\"a\":\n1}"),
      ServerSentEvent(name: nil, data: "[DONE]"),
    ])
  }

  func testOpenAIToolCallsArriveInFragments() throws {
    var reply = OpenAIChatClient.ReplyBuilder()
    let chunks = [
      #"{"choices":[{"delta":{"content":"Let me look."}}]}"#,
      #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_tolerance","arguments":"{\"subs"}}]}}]}"#,
      #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tance\":\"LSD\"}"}}]},"finish_reason":"tool_calls"}],"error":null}"#,
    ]
    var texts: [String] = []
    for chunk in chunks {
      if let text = try reply.add(XCTUnwrap(JSONValue(jsonText: chunk))) {
        texts.append(text)
      }
    }
    let finished = try reply.finish()
    XCTAssertEqual(texts, ["Let me look."])
    XCTAssertEqual(finished.text, "Let me look.")
    XCTAssertEqual(finished.toolCalls, [AssistantToolCall(id: "call_1", name: "get_tolerance", arguments: ["substance": "LSD"])])
  }

  func testOpenAIContentFilterWithoutAnswerFails() throws {
    var reply = OpenAIChatClient.ReplyBuilder()
    _ = try reply.add(XCTUnwrap(JSONValue(jsonText: #"{"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#)))
    XCTAssertThrowsError(try reply.finish())
  }

  func testAnthropicBlocksAreRebuiltFromTheStream() throws {
    var message = AnthropicMessagesClient.MessageBuilder()
    let events = [
      #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}"#,
      #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
      #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Checking."}}"#,
      #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"check_interactions","input":{}}}"#,
      #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"substances\":[\"MDMA\","}}"#,
      #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"Alcohol\"]}"}}"#,
      #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
    ]
    var texts: [String] = []
    for event in events {
      texts += try message.add(XCTUnwrap(JSONValue(jsonText: event)), named: nil)
    }
    let reply = try message.finish()
    XCTAssertEqual(texts, ["Checking."])
    XCTAssertEqual(reply.text, "Checking.")
    XCTAssertEqual(reply.toolCalls.first?.arguments["substances"], .array(["MDMA", "Alcohol"]))
    let blocks = try XCTUnwrap(reply.native?.content.array)
    XCTAssertEqual(blocks.map { $0["type"]?.string }, ["thinking", "text", "tool_use"])
    XCTAssertEqual(blocks[0]["signature"], "sig")
  }

  func testAnthropicRefusalDiscardsTheAnswer() throws {
    var message = AnthropicMessagesClient.MessageBuilder()
    _ = try message.add(
      XCTUnwrap(JSONValue(jsonText: #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Sure"}}"#)),
      named: nil)
    _ = try message.add(
      XCTUnwrap(
        JSONValue(jsonText: #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"category":"cyber"}}}"#)),
      named: nil)
    XCTAssertThrowsError(try message.finish()) { error in
      XCTAssertEqual((error as? AssistantError)?.discardsPartialText, true)
    }
  }

  func testAnthropicKeepsOnlyTextBeforeAFallback() {
    let blocks: [JSONValue] = [
      .object(["type": "thinking", "thinking": "", "signature": "a"]),
      .object(["type": "text", "text": "Partial"]),
      .object(["type": "fallback"]),
      .object(["type": "thinking", "thinking": "", "signature": "b"]),
      .object(["type": "text", "text": " rest"]),
      .object(["type": "server_thing"]),
    ]
    XCTAssertEqual(AnthropicMessagesClient.echoedBlocks(blocks), [blocks[1], blocks[3], blocks[4]])
  }

  func testGeminiThoughtsAreNotPartOfTheAnswer() throws {
    var reply = GeminiClient.ReplyBuilder()
    let chunk = #"{"candidates":[{"content":{"parts":[{"text":"pondering","thought":true},{"text":"Hi"},{"functionCall":{"name":"get_active_ingestions","args":{"hours_back":12}},"thoughtSignature":"x"}]}}]}"#
    XCTAssertEqual(try reply.add(XCTUnwrap(JSONValue(jsonText: chunk))), ["Hi"])
    let finished = try reply.finish()
    XCTAssertEqual(finished.text, "Hi")
    XCTAssertEqual(finished.toolCalls.first?.arguments, ["hours_back": .number(12)])
    XCTAssertEqual(finished.native?.content.array?.count, 3)
  }

  func testGeminiSchemasUseCapitalTypes() {
    let schema: JSONValue = .object([
      "type": "object",
      "properties": .object(["names": .object(["type": "array", "items": .object(["type": "string"])])]),
    ])
    let converted = GeminiClient.upperCasingTypes(in: schema)
    XCTAssertEqual(converted["type"], "OBJECT")
    XCTAssertEqual(converted["properties"]?["names"]?["items"]?["type"], "STRING")
  }

  func testOnlyLocalServersMayUseHTTP() {
    XCTAssertNoThrow(try AssistantHTTP.url("http://localhost:11434/v1", "models"))
    XCTAssertThrowsError(try AssistantHTTP.url("http://192.168.1.2:11434/v1", "models"))
    XCTAssertEqual(
      try AssistantHTTP.url("https://api.example.com/v1/", "/models").absoluteString,
      "https://api.example.com/v1/models")
  }
}
