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
    let file = try JournalFile(experiences: [], customSubstances: [], customUnits: [], formulations: [formulation])
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

  func testFormulationIngestionsAreSuggestedAsTheFormulation() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: context)
    var ingestions = [Ingestion]()
    for (index, arguments) in formulation.ingestionArguments(amount: 1.5).enumerated() {
      let ingestion = Ingestion(context: context)
      ingestion.substanceName = arguments.substanceName
      ingestion.administrationRoute = arguments.administrationRoute.rawValue
      ingestion.dose = arguments.dose ?? 0
      ingestion.units = arguments.units
      ingestion.formulation = arguments.formulation
      ingestion.formulationAmount = arguments.formulationAmount ?? 0
      ingestion.creationDate = Date(timeIntervalSince1970: 2_000 + Double(index))
      ingestions.append(ingestion)
    }
    let alone = Ingestion(context: context)
    alone.substanceName = "MDMA"
    alone.administrationRoute = AdministrationRoute.oral.rawValue
    alone.dose = 80
    alone.units = "mg"
    alone.creationDate = Date(timeIntervalSince1970: 1_000)
    ingestions.append(alone)

    let suggestions = getSuggestions(sortedIngestions: ingestions, customUnits: [])
    let formulationSuggestions = suggestions.compactMap { $0 as? FormulationSuggestions }
    XCTAssertEqual(formulationSuggestions.map(\.formulation), [formulation])
    XCTAssertEqual(formulationSuggestions.first?.amounts, [1.5])
    XCTAssertTrue(suggestions.first is FormulationSuggestions)
    let pure = suggestions.compactMap { $0 as? PureSubstanceSuggestions }
    XCTAssertEqual(pure.map(\.substance.name), ["MDMA"])
    XCTAssertEqual(pure.first?.dosesAndUnit.map(\.dose), [80])
  }

  func testIngestionsKeepTheirFormulationThroughExportWhenNamesMatch() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let other = sample.insert(into: source)
    other.note = "Different formulation with the same name"
    let formulation = sample.insert(into: source)
    let experience = Experience.create(at: Date(timeIntervalSince1970: 5_000), title: "Test", in: source)
    let ingestion = Ingestion(context: source)
    ingestion.substanceName = "MDMA"
    ingestion.time = Date(timeIntervalSince1970: 5_000)
    ingestion.administrationRoute = AdministrationRoute.oral.rawValue
    ingestion.formulation = formulation
    ingestion.formulationAmount = 2
    ingestion.experience = experience
    let file = try JournalFile(experiences: [experience], customSubstances: [], customUnits: [], formulations: [other, formulation])
    let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
    let target = PersistenceController(inMemory: true).viewContext
    decoded.insert(into: target)

    let imported = try XCTUnwrap(target.fetch(Ingestion.fetchRequest()).first)
    XCTAssertEqual(imported.formulation?.nameUnwrapped, "Party pill")
    XCTAssertEqual(imported.formulation?.note, formulation.note)
    XCTAssertEqual(imported.formulationAmount, 2)

    let data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
    var oldRecords = try XCTUnwrap(data["experiences"] as? [[String: Any]])
    var oldIngestions = try XCTUnwrap(oldRecords[0]["ingestions"] as? [[String: Any]])
    oldIngestions[0].removeValue(forKey: "formulationId")
    oldRecords[0]["ingestions"] = oldIngestions
    var oldJSON = data
    oldJSON["experiences"] = oldRecords
    let oldFile = try JournalFile.read(JSONSerialization.data(withJSONObject: oldJSON))
    let oldTarget = PersistenceController(inMemory: true).viewContext
    oldFile.insert(into: oldTarget)
    XCTAssertNil(try oldTarget.fetch(Ingestion.fetchRequest()).first?.formulation)
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
