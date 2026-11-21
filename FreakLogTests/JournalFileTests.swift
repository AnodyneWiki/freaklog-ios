import CoreData
@testable import FreakLog
import XCTest

@MainActor
final class JournalFileTests: XCTestCase {
    func testExportedJournalImportsTheSameData() throws {
        let source = PersistenceController(inMemory: true).viewContext
        let unit = CustomUnit(context: source)
        unit.idForAndroid = 7
        unit.substanceName = "Ketamine"
        unit.name = "Spoon"
        unit.unit = "spoon"
        unit.originalUnit = "mg"
        unit.dose = 20
        unit.administrationRoute = AdministrationRoute.insufflated.rawValue
        unit.creationDate = Date(timeIntervalSince1970: 1_000)

        let experience = Experience.create(at: Date(timeIntervalSince1970: 5_000), title: "Test", in: source)
        experience.isFavorite = true
        let ingestion = Ingestion(context: source)
        ingestion.substanceName = "Ketamine"
        ingestion.time = Date(timeIntervalSince1970: 5_000)
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.dose = 2
        ingestion.units = "spoon"
        ingestion.consumerName = "Someone"
        ingestion.customUnit = unit
        ingestion.experience = experience
        let rating = ShulginRating(context: source)
        rating.creationDate = Date(timeIntervalSince1970: 6_000)
        rating.option = ShulginRatingOption.twoPlus.rawValue
        rating.experience = experience
        let customSubstance = CustomSubstance(context: source)
        customSubstance.name = "Coffee"
        customSubstance.units = "cups"
        customSubstance.explanation = "Bitter"

        let file = JournalFile(experiences: [experience], customSubstances: [customSubstance], customUnits: [unit])
        let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
        let target = PersistenceController(inMemory: true).viewContext
        decoded.insert(into: target)

        let importedExperience = try XCTUnwrap(target.fetch(Experience.fetchRequest()).first)
        XCTAssertEqual(importedExperience.title, "Test")
        XCTAssertTrue(importedExperience.isFavorite)
        XCTAssertEqual(importedExperience.ratingsUnwrapped.first?.optionUnwrapped, .twoPlus)
        let importedIngestion = try XCTUnwrap(importedExperience.ingestionsSorted.first)
        XCTAssertEqual(importedIngestion.time, ingestion.time)
        XCTAssertEqual(importedIngestion.dose, 2)
        XCTAssertEqual(importedIngestion.consumerName, "Someone")
        XCTAssertEqual(importedIngestion.customUnit?.nameUnwrapped, "Spoon")
        XCTAssertEqual(importedIngestion.customUnit?.dose, 20)
        XCTAssertNotNil(importedIngestion.identifier)
        XCTAssertEqual(importedIngestion.substanceCompanion?.substanceName, "Ketamine")
        let importedSubstance = try XCTUnwrap(target.fetch(CustomSubstance.fetchRequest()).first)
        XCTAssertEqual(importedSubstance.units, "cups")
        XCTAssertEqual(importedSubstance.explanation, "Bitter")
    }
}
