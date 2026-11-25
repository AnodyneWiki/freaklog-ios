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

  func testWebSearchToolIsOptInAndIndependentOfModelProvider() {
    let context = PersistenceController(inMemory: true).viewContext
    let defaultTools = AssistantToolbox(context: context, includesAnodyneWiki: false)
    let enabledTools = AssistantToolbox(
      context: context, includesAnodyneWiki: false, includesWebAccess: true)
    XCTAssertFalse(defaultTools.specs.contains { $0.name == "search_web" })
    XCTAssertTrue(enabledTools.specs.contains { $0.name == "search_web" })
    XCTAssertFalse(defaultTools.specs.contains { $0.name == "lookup_wikipedia" })
    XCTAssertTrue(enabledTools.specs.contains { $0.name == "lookup_wikipedia" })
  }

  func testWikipediaUsesOneBoundedLookupWithSourceLinks() throws {
    let lookup = AssistantWikipedia.requestBody(query: "Ada Lovelace", mode: .summary, language: "de")
    XCTAssertEqual(lookup["params"]?["name"], "wikipedia_get_summary")
    XCTAssertEqual(lookup["params"]?["arguments"], .object(["title": "Ada Lovelace", "language": "de"]))

    let search = AssistantWikipedia.requestBody(query: "Lovelace", mode: .search, language: "en")
    XCTAssertEqual(search["params"]?["name"], "wikipedia_search_articles")
    XCTAssertEqual(search["params"]?["arguments"]?["limit"], .number(3))
    let reply: JSONValue = .object([
      "result": .object([
        "structuredContent": .object([
          "title": "Ada Lovelace",
          "extract": "English mathematician and writer.",
          "page_type": "standard",
        ]),
      ]),
    ])
    let summary = try AssistantWikipedia.result(from: reply, mode: .summary, language: "de", textLimit: 10)
    XCTAssertEqual(summary["summary"], "English ma…")
    XCTAssertEqual(summary["url"], "https://de.wikipedia.org/wiki/Ada_Lovelace")
    XCTAssertEqual(summary["page_type"], "standard")
    XCTAssertThrowsError(try AssistantWikipedia.result(from: .object([:]), mode: .search, language: "en", textLimit: 10))
  }

  func testWebSearchSendsOnlyTheQueryAndPreservesSourceLinks() throws {
    let request = AssistantWebSearch.requestBody(query: "SwiftUI toolbar")
    XCTAssertEqual(request["method"], "tools/call")
    XCTAssertEqual(request["params"]?["name"], "web_search_exa")
    XCTAssertEqual(request["params"]?["arguments"], .object(["query": "SwiftUI toolbar", "numResults": .number(3)]))

    let reply: JSONValue = .object([
      "result": .object([
        "content": .array([.object([
          "type": "text",
          "text": "Title: First\nURL: https://example.com/one\nHighlights:\nFirst excerpt.\n\n---\n\nTitle: Second\nURL: https://example.com/two\nHighlights:\nSecond excerpt.",
        ])]),
      ]),
    ])
    let result = try AssistantWebSearch.result(from: reply, textLimit: 800)
    let sources = try XCTUnwrap(result["results"]?.array?.compactMap(\.string))
    XCTAssertEqual(sources.count, 2)
    XCTAssertTrue(sources[0].contains("https://example.com/one"))
    XCTAssertTrue(sources[1].contains("https://example.com/two"))
    let markdown = AssistantWebSearch.markdown(from: result)
    XCTAssertTrue(markdown.contains("[example.com](<https://example.com/one>)"))
    XCTAssertTrue(markdown.contains("[example.com](<https://example.com/two>)"))
    XCTAssertEqual(AssistantWebSearch.markdown(from: .object(["results": .array([])])), "No web results found.")
    XCTAssertThrowsError(try AssistantWebSearch.result(
      from: .object(["error": .object(["message": "Rate limited"])]), textLimit: 800))
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
