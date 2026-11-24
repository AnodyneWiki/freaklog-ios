import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class AssistantToolTests: XCTestCase {
  func testToolsFindExperiencesBySubstanceAndOpenThem() async throws {
    let context = PersistenceController(inMemory: true).viewContext
    let experience = Experience.create(at: Date(timeIntervalSince1970: 1_795_287_600), title: "Saturday", in: context)
    experience.text = "Danced all night"
    let ingestion = Ingestion(context: context)
    ingestion.substanceName = "MDMA"
    ingestion.time = Date(timeIntervalSince1970: 1_795_287_600)
    ingestion.dose = 100
    ingestion.units = "mg"
    ingestion.administrationRoute = AdministrationRoute.oral.rawValue
    ingestion.experience = experience
    try context.save()
    let toolbox = AssistantToolbox(context: context, includesAnodyneWiki: false)

    let found = await toolbox.run(AssistantToolCall(
      id: nil,
      name: "search_experiences_by_substance",
      arguments: ["substance": "mdm"]))
    let reference = try XCTUnwrap(found["matches"]?.array?.first?["experience_id"]?.string)
    let details = await toolbox.run(AssistantToolCall(
      id: nil,
      name: "get_experience_details",
      arguments: ["experience_id": .string(reference), "max_notes_chars": "6"]))
    XCTAssertEqual(details["title"], "Saturday")
    XCTAssertEqual(details["notes"], "Danced")
    XCTAssertEqual(details["notes_truncated"], .bool(true))
    XCTAssertEqual(details["ingestions"]?.array?.first?["dose"], .number(100))
    let call = AssistantToolCall(id: nil, name: "get_experience_details", arguments: ["experience_id": .string(reference)])
    XCTAssertEqual(toolbox.progress(for: call), "Reading the session…")
  }

  func testToolsRejectBrokenCalls() async {
    let toolbox = makeToolbox()
    let unknown = await toolbox.run(AssistantToolCall(id: nil, name: "drop_database", arguments: [:]))
    XCTAssertEqual(unknown["status"], "error")
    let broken = await toolbox.run(AssistantToolCall(id: nil, name: "get_tolerance", arguments: [:], hasInvalidArguments: true))
    XCTAssertEqual(broken["status"], "error")
  }

  func testInteractionsAreCheckedByTheAppsNames() async {
    let result = await makeToolbox().run(AssistantToolCall(
      id: nil,
      name: "check_interactions",
      arguments: ["substances": .array(["Molly", "ethanol"])]))
    XCTAssertEqual(result["substances"], .array(["MDMA", "Alcohol"]))
    XCTAssertEqual(result["interactions"]?.array?.first?["risk"]?.string?.isEmpty, false)
  }

  func testActiveIngestionsUseOnlyPersonalEntriesThatHaveStarted() async throws {
    let context = PersistenceController(inMemory: true).viewContext
    for (name, consumer, offset) in [("Personal", nil, -60.0), ("Other", "Guest", -60.0), ("Future", nil, 3600.0)] {
      let ingestion = Ingestion(context: context)
      ingestion.substanceName = name
      ingestion.consumerName = consumer
      ingestion.time = Date.now.addingTimeInterval(offset)
    }
    try context.save()
    let toolbox = AssistantToolbox(context: context, includesAnodyneWiki: false)
    let result = await toolbox.run(AssistantToolCall(id: nil, name: "get_active_ingestions", arguments: [:]))
    let entries = try XCTUnwrap(result["ingestions"]?.array)
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?["substance"], "Personal")
  }

  func testSchemasListRequiredParameters() {
    let schema = AssistantToolbox.schema(of: [
      .init(name: "substance", description: "", kind: .string, isRequired: true),
      .init(name: "names", description: "", kind: .stringArray),
    ])
    XCTAssertEqual(schema["required"], .array(["substance"]))
    XCTAssertEqual(schema["properties"]?["names"]?["items"]?["type"], "string")
  }

  func testWebSearchToolIsOptInAndChecksProvider() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let search = try XCTUnwrap(AssistantWebSearch(profile: AssistantProfile(preset: .openAI), apiKey: "fixture"))
    let defaultTools = AssistantToolbox(context: context, includesAnodyneWiki: false)
    let enabledTools = AssistantToolbox(
      context: context, includesAnodyneWiki: false, webSearch: search.tool(textLimit: 800) { "test-model" })
    XCTAssertFalse(defaultTools.specs.contains { $0.name == "search_web" })
    XCTAssertTrue(enabledTools.specs.contains { $0.name == "search_web" })
    XCTAssertNil(AssistantWebSearch(profile: AssistantProfile(preset: .gemini), apiKey: "fixture"))
    XCTAssertNil(AssistantWebSearch(profile: AssistantProfile(preset: .onDevice), apiKey: ""))
    var customServer = AssistantProfile(preset: .openAI)
    customServer.baseURL = "https://api.openai.com.example.org/v1"
    XCTAssertNil(AssistantWebSearch(profile: customServer, apiKey: "fixture"))
  }

  func testWebSearchUsesEachProvidersBuiltInTool() throws {
    for (preset, path, type) in [
      (AssistantPreset.openAI, "/v1/responses", "web_search"),
      (.anthropic, "/v1/messages", "web_search_20250305"),
      (.openRouter, "/api/v1/chat/completions", "openrouter:web_search"),
    ] {
      let search = try XCTUnwrap(AssistantWebSearch(profile: AssistantProfile(preset: preset), apiKey: "fixture"))
      let body = search.requestBody(query: "current weather in Berlin", model: "test-model")
      XCTAssertEqual(search.url.path, path)
      XCTAssertEqual(body["model"], "test-model")
      XCTAssertEqual(body["tools"]?.array?.first?["type"], .string(type))
      XCTAssertTrue(body.jsonText.contains("current weather in Berlin"))
      XCTAssertFalse(body.jsonText.contains("fixture"))
    }
  }

  func testWebSearchPreservesProviderCitations() throws {
    let examples: [(AssistantPreset, String)] = [
      (.openAI, """
      {"output":[{"type":"message","content":[{"type":"output_text","text":"Result","annotations":[
        {"url":"https://example.com/article","title":"An Article"}, {"url":"freaklog://example.com","title":"Invalid"}
      ]}]}]}
      """),
      (.anthropic, """
      {"content":[{"type":"text","text":"Result","citations":[{"url":"https://example.com/article","title":"An Article"}]}]}
      """),
      (.openRouter, """
      {"choices":[{"message":{"content":"Result","annotations":[
        {"type":"url_citation","url_citation":{"url":"https://example.com/article","title":"An Article"}}
      ]}}]}
      """),
    ]
    for (preset, json) in examples {
      let search = try XCTUnwrap(AssistantWebSearch(profile: AssistantProfile(preset: preset), apiKey: "fixture"))
      let result = try search.result(from: XCTUnwrap(JSONValue(jsonText: json)), textLimit: 80)
      XCTAssertEqual(result["summary"], "Result")
      XCTAssertEqual(result["sources"], .array([.object(["url": "https://example.com/article", "title": "An Article"])]))
      XCTAssertThrowsError(try search.result(from: .object([:]), textLimit: 80))
    }
  }

  func testArgumentsAreClamped() {
    let arguments: [String: JSONValue] = ["limit": "500", "days": .number(-3), "huge": .number(1e100)]
    XCTAssertEqual(arguments.integer("huge", default: 10, in: 1 ... 50), 50)
    XCTAssertEqual(arguments.integer("limit", default: 10, in: 1 ... 50), 50)
    XCTAssertEqual(arguments.integer("days", default: 30, in: 1 ... 730), 1)
    XCTAssertEqual(arguments.integer("missing", default: 30, in: 1 ... 730), 30)
  }

  private func makeToolbox() -> AssistantToolbox {
    AssistantToolbox(context: PersistenceController(inMemory: true).viewContext, includesAnodyneWiki: false)
  }
}
