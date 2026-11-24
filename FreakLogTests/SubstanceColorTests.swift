import SwiftUI
import XCTest
@testable import FreakLog

@MainActor
final class SubstanceColorTests: XCTestCase {
  func testReadsHexCodes() {
    XCTAssertEqual(SubstanceColor(hex: "#0a84ff")?.hex, "#0A84FF")
    XCTAssertEqual(SubstanceColor(hex: "123ABC")?.hex, "#123ABC")
    XCTAssertNil(SubstanceColor(hex: "#12345"))
    XCTAssertNil(SubstanceColor(hex: "#GGGGGG"))
    XCTAssertNil(SubstanceColor(hex: ""))
  }

  func testReadsTheNamesOfTheOldPalette() {
    XCTAssertEqual(SubstanceColor(rawValue: "FIRE_ENGINE_RED")?.hex, "#ED2B2A")
    XCTAssertEqual(SubstanceColor(rawValue: "blue"), .blue)
    XCTAssertEqual(SubstanceColor(rawValue: "#BF5AF2"), .purple)
    XCTAssertNil(SubstanceColor(rawValue: "NOT_A_COLOR"))
  }

  func testPaletteColorsAreDistinctAndKeepTheirNames() {
    XCTAssertEqual(SubstanceColor.palette.count, 51)
    XCTAssertEqual(Set(SubstanceColor.palette).count, 51)
    XCTAssertEqual(SubstanceColor.fireEngineRed.name, "fire engine red")
    XCTAssertTrue(SubstanceColor.blue.isInPalette)
    let custom = SubstanceColor(hex: "#123456")
    XCTAssertEqual(custom?.isInPalette, false)
    XCTAssertEqual(custom?.name, "#123456")
  }

  func testExportsPaletteNamesAndOtherwiseCodes() throws {
    XCTAssertEqual(SubstanceColor.blue.exportValue, "BLUE")
    XCTAssertEqual(SubstanceColor(hex: "#123456")?.exportValue, "#123456")
    let json = try JSONEncoder().encode(CompanionCodable(substanceName: "MDMA", color: .hotPink))
    XCTAssertTrue(String(decoding: json, as: UTF8.self).contains(#""color":"HOT_PINK""#))
    let decoded = try JSONDecoder().decode(CompanionCodable.self, from: json)
    XCTAssertEqual(decoded.color, .hotPink)
    let custom = try JSONDecoder().decode(
      CompanionCodable.self,
      from: Data(##"{"substanceName": "MDMA", "color": "#123456"}"##.utf8))
    XCTAssertEqual(custom.color.hex, "#123456")
  }

  func testConvertsPickedColors() {
    XCTAssertEqual(SubstanceColor(Color(.sRGB, red: 1, green: 0.5, blue: 0)).hex, "#FF8000")
    XCTAssertEqual(SubstanceColor(Color(.sRGB, red: 0, green: 0, blue: 0)).hex, "#000000")
  }

  func testSuggestionsStayApartFromTheColorsInUse() throws {
    let used: [SubstanceColor] = [.blue, .red, .green, .orange, .purple, .yellow, .pink, .teal]
    let suggestions = SubstanceColor.distinctColors(from: used, count: 12)
    XCTAssertEqual(suggestions.count, 12)
    XCTAssertEqual(Set(suggestions).count, 12)
    XCTAssertTrue(Set(suggestions).isDisjoint(with: used))
    // Each suggestion is at least as far from the others as a much later one would be
    let minimumDistance = { (color: SubstanceColor, others: [SubstanceColor]) in
      others.map { color.distance(to: $0) }.min() ?? .infinity
    }
    for (index, suggestion) in suggestions.enumerated() {
      XCTAssertGreaterThan(minimumDistance(suggestion, used + suggestions[..<index]), 0.05, suggestion.hex)
    }
    XCTAssertEqual(SubstanceColor.distinctColors(from: used, count: 12), suggestions)
  }

  func testSuggestionsAvoidAColorCloseToOneInUse() {
    let suggestion = SubstanceColor.suggested(avoiding: [.blue])
    XCTAssertGreaterThan(suggestion.distance(to: .blue), 0.2)
    let first = SubstanceColor.suggested(avoiding: [])
    XCTAssertNotEqual(SubstanceColor.suggested(avoiding: [first]), first)
  }

  func testSuggestsEvenWithManyColorsInUse() {
    let suggestions = SubstanceColor.distinctColors(from: SubstanceColor.palette, count: 30)
    XCTAssertEqual(Set(suggestions).count, 30)
    XCTAssertTrue(Set(suggestions).isDisjoint(with: SubstanceColor.palette))
  }

  func testMigrationStoresHexCodes() throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let companion = SubstanceCompanion(context: context)
    companion.colorAsText = "BLUE"
    let ingestion = Ingestion(context: context)
    ingestion.color = "FIRE_ENGINE_RED"
    let note = TimedNote(context: context)
    note.colorAsText = "MINT"
    let custom = SubstanceCompanion(context: context)
    custom.colorAsText = "#123456"
    let unreadable = SubstanceCompanion(context: context)
    unreadable.colorAsText = "nonsense"
    try context.save()

    persistence.migrateColorsToHex()

    XCTAssertEqual(companion.colorAsText, "#0A84FF")
    XCTAssertEqual(ingestion.color, "#ED2B2A")
    XCTAssertEqual(note.colorAsText, "#63E6E2")
    XCTAssertEqual(custom.colorAsText, "#123456")
    XCTAssertEqual(unreadable.colorAsText, "nonsense")
    XCTAssertEqual(companion.color, .blue)
  }
}
