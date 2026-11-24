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

  func testSuggestsUnusedPaletteColorsFirst() {
    XCTAssertEqual(SubstanceColor.suggested(avoiding: [.blue]), .brown)
    XCTAssertFalse(SubstanceColor.unused(avoiding: [.blue, .red]).contains(.red))
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
