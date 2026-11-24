import CoreData
import XCTest
@testable import FreakLog

// MARK: - FormulationTests

@MainActor
final class FormulationTests: XCTestCase {
  func testAmountScalesDosesAndDeviations() {
    let arguments = sample.ingestionArguments(amount: 1.5)
    XCTAssertEqual(arguments.map(\.substanceName), ["MDMA", "Caffeine", "Ketamine"])
    XCTAssertEqual(arguments[0].dose, 150)
    XCTAssertEqual(arguments[0].estimatedDoseStandardDeviation, 15)
    XCTAssertTrue(arguments[0].isEstimate)
    XCTAssertEqual(arguments[1].dose, 75)
    XCTAssertNil(arguments[1].estimatedDoseStandardDeviation)
    XCTAssertNil(arguments[2].dose)
    XCTAssertEqual(arguments[2].administrationRoute, .insufflated)
    XCTAssertEqual(arguments[2].units, "mg")
  }

  func testComponentsKeepTheirOrderWhenSaved() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: context)
    try context.save()
    XCTAssertEqual(formulation.componentsSorted.map(\.substanceNameUnwrapped), ["MDMA", "Caffeine", "Ketamine"])

    var edited = FormulationCodable(formulation)
    edited.components.reverse()
    edited.components.removeLast()
    edited.apply(to: formulation)
    try context.save()
    XCTAssertEqual(formulation.componentsSorted.map(\.substanceNameUnwrapped), ["Ketamine", "Caffeine"])
    XCTAssertEqual(try context.count(for: FormulationComponent.fetchRequest()), 2)
  }

  func testExportedFormulationsImportTheSameData() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: source)
    let file = JournalFile(experiences: [], customSubstances: [], customUnits: [], formulations: [formulation])
    let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
    let target = PersistenceController(inMemory: true).viewContext
    decoded.insert(into: target)

    let imported = try XCTUnwrap(target.fetch(Formulation.fetchRequest()).first)
    let values = FormulationCodable(imported)
    XCTAssertEqual(values.name, sample.name)
    XCTAssertEqual(values.note, sample.note)
    XCTAssertEqual(values.creationDate, sample.creationDate)
    XCTAssertEqual(values.components.map(\.withoutID), sample.components.map(\.withoutID))
  }

  func testOlderFilesWithoutFormulationsStillImport() throws {
    let file = try JSONDecoder().decode(JournalFile.self, from: Data(#"{"experiences": []}"#.utf8))
    XCTAssertTrue(file.formulations.isEmpty)
  }

  func testDeletingAFormulationDeletesItsComponents() throws {
    let context = PersistenceController(inMemory: true).viewContext
    context.delete(sample.insert(into: context))
    try context.save()
    XCTAssertEqual(try context.count(for: FormulationComponent.fetchRequest()), 0)
  }

  private let sample = FormulationCodable(
    name: "Party pill",
    note: "Tested",
    creationDate: Date(timeIntervalSince1970: 1_000),
    components: [
      .init(
        substanceName: "MDMA",
        administrationRoute: .oral,
        dose: 100,
        units: "mg",
        isEstimate: true,
        estimatedDoseStandardDeviation: 10),
      .init(
        substanceName: "Caffeine",
        administrationRoute: .oral,
        dose: 50,
        units: "mg",
        isEstimate: false,
        estimatedDoseStandardDeviation: nil),
      .init(
        substanceName: "Ketamine",
        administrationRoute: .insufflated,
        dose: nil,
        units: "mg",
        isEstimate: false,
        estimatedDoseStandardDeviation: nil),
    ])
}

extension FormulationCodable.Component {
  // Ids only tell components apart while editing
  fileprivate var withoutID: Self {
    var copy = self
    copy.id = UUID(uuid: UUID_NULL)
    return copy
  }
}
