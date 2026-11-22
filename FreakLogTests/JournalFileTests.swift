import CoreData
@testable import FreakLog
import XCTest

@MainActor
final class JournalFileTests: XCTestCase {
    func testDatesAreWrittenAsWholeMilliseconds() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            TimedNoteCodable(
                creationDate: Date(timeIntervalSince1970: 1.5),
                time: Date(timeIntervalSince1970: 2),
                note: "",
                color: .blue,
                isPartOfTimeline: false
            )
        )) as? [String: Any]
        XCTAssertEqual(json?["creationDate"] as? Int64, 1_500)
        XCTAssertEqual(json?["time"] as? Int64, 2_000)
    }

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
        ingestion.time = Date(timeIntervalSince1970: 5_000.25)
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

        rating.time = nil

        let override = SubstanceOverride(context: source)
        override.substanceName = "Coffee"
        override.categoryList = ["stimulant"]
        let pwOverride = SubstanceOverride(context: source)
        pwOverride.substanceName = "Ketamine"
        pwOverride.displayName = "K"

        let file = JournalFile(
            experiences: [experience],
            customSubstances: [customSubstance],
            customUnits: [unit],
            substanceOverrides: [override, pwOverride]
        )
        let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
        let target = PersistenceController(inMemory: true).viewContext
        decoded.insert(into: target)

        let importedExperience = try XCTUnwrap(target.fetch(Experience.fetchRequest()).first)
        XCTAssertEqual(importedExperience.title, "Test")
        XCTAssertTrue(importedExperience.isFavorite)
        XCTAssertEqual(importedExperience.ratingsUnwrapped.first?.optionUnwrapped, .twoPlus)
        XCTAssertNil(importedExperience.ratingsUnwrapped.first?.time)
        XCTAssertEqual(importedExperience.sortDate, experience.sortDate)
        let importedIngestion = try XCTUnwrap(importedExperience.ingestionsSorted.first)
        XCTAssertEqual(importedIngestion.time, ingestion.time)
        XCTAssertNil(importedIngestion.endTime)
        XCTAssertEqual(importedIngestion.dose, 2)
        XCTAssertEqual(importedIngestion.consumerName, "Someone")
        XCTAssertEqual(importedIngestion.customUnit?.nameUnwrapped, "Spoon")
        XCTAssertEqual(importedIngestion.customUnit?.dose, 20)
        XCTAssertNotNil(importedIngestion.identifier)
        XCTAssertEqual(importedIngestion.substanceCompanion?.substanceName, "Ketamine")
        let importedSubstance = try XCTUnwrap(target.fetch(CustomSubstance.fetchRequest()).first)
        XCTAssertEqual(importedSubstance.units, "cups")
        XCTAssertEqual(importedSubstance.explanation, "Bitter")
        let importedOverrides = try target.fetch(SubstanceOverride.fetchRequest())
        XCTAssertEqual(importedOverrides.first { $0.substanceName == "Coffee" }?.categoryList, ["stimulant"])
        XCTAssertEqual(importedOverrides.first { $0.substanceName == "Ketamine" }?.displayName, "K")
        XCTAssertNil(importedOverrides.first { $0.substanceName == "Ketamine" }?.categoryList)
    }

    func testPrimaryCategorySkipsTags() {
        // Overrides saved before toggling kept the order had the category list's order, common first
        XCTAssertEqual(PersistenceController.primaryCategory(of: ["common", "stimulant"]), "stimulant")
        XCTAssertEqual(PersistenceController.primaryCategory(of: ["research-chemical", "tentative", "opioid"]), "opioid")
        // Only tags: Cannabis keeps sending its first category
        XCTAssertEqual(PersistenceController.primaryCategory(of: ["habit-forming", "common"]), "habit-forming")
        XCTAssertNil(PersistenceController.primaryCategory(of: []))
    }

    func testMergedOverrideDependsOnlyOnValues() {
        let named = SubstanceOverrideCache.Entry(displayName: "Coffee", categories: [])
        let categorized = SubstanceOverrideCache.Entry(displayName: nil, categories: ["stimulant"])
        let renamed = SubstanceOverrideCache.Entry(displayName: "Kaffee", categories: nil)
        XCTAssertEqual(named.merged(categorized), SubstanceOverrideCache.Entry(displayName: "Coffee", categories: ["stimulant"]))
        XCTAssertEqual(named.merged(categorized), categorized.merged(named))
        XCTAssertEqual(named.merged(renamed), renamed.merged(named))
        XCTAssertEqual(named.merged(renamed).displayName, "Kaffee")
        // An empty list is still the user's choice over the default
        XCTAssertEqual(renamed.merged(named).categories, [])
    }

    func testDuplicateOverridesCollapseOnSave() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        // One row from each device, synced by iCloud
        let first = SubstanceOverride(context: context)
        first.substanceName = "Caffeine"
        first.displayName = "Coffee"
        let second = SubstanceOverride(context: context)
        second.substanceName = "Caffeine"
        second.categoryList = ["stimulant"]
        try context.save()
        let merged = try XCTUnwrap(persistence.substanceOverride(for: "Caffeine"))
        XCTAssertEqual(merged, SubstanceOverrideCache.Entry(displayName: "Coffee", categories: ["stimulant"]))
        let exported = SubstanceDataOverrideCodable.grouped([], overrides: [first, second])
        XCTAssertEqual(exported.map(\.categories), [["stimulant"]])
        XCTAssertEqual(exported.map(\.displayName), ["Coffee"])

        persistence.setSubstanceOverride(for: "Caffeine", displayName: merged.displayName, categories: ["stimulant", "common"])
        let rows = try context.fetch(PersistenceController.substanceOverridesRequest(for: "Caffeine"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.displayName, "Coffee")
        XCTAssertEqual(rows.first?.categoryList, ["stimulant", "common"])

        persistence.setSubstanceOverride(for: "Caffeine", displayName: nil, categories: nil)
        XCTAssertEqual(try context.count(for: PersistenceController.substanceOverridesRequest(for: "Caffeine")), 0)
    }
}
