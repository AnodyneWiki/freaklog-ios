import CoreData
@testable import FreakLog
import XCTest

@MainActor
final class JournalFileTests: XCTestCase {
    func testJournalImportRejectsAnEmptyUnidentifiedFile() throws {
        let decoder = JSONDecoder()
        for json in ["{}", #"{"customUnits":[]}"#, #"{"experiences":null}"#, #"{"experiences":{}}"#] {
            XCTAssertThrowsError(try decoder.decode(JournalFile.self, from: Data(json.utf8)), json)
        }
        let emptyJournal = try decoder.decode(JournalFile.self, from: Data(#"{"experiences":[]}"#.utf8))
        XCTAssertTrue(emptyJournal.experiences.isEmpty)
    }

    func testLegacyAndroidImportsCustomDataWithoutExperiencesAndOptionalFields() throws {
        let customOnly = try JournalFile.read(Data(#"{"customSubstances":[{"name":"Example","units":"g","description":""}]}"#.utf8))
        XCTAssertEqual(customOnly.customSubstances.map(\.name), ["Example"])
        XCTAssertTrue(customOnly.experiences.isEmpty)

        let legacy = try JournalFile.read(Data(#"""
          {"experiences":[{"title":"Example","text":"","sortDate":1700000000000,
          "ingestions":[{"substanceName":"Example","time":1700000000000,"administrationRoute":"ORAL","isDoseAnEstimate":false}],
          "ratings":[{"option":"twoPlus","creationDate":null}]}]}
          """#.utf8))
        let experience = try XCTUnwrap(legacy.experiences.first)
        let ingestion = try XCTUnwrap(experience.ingestions.first)
        XCTAssertEqual(ingestion.units, "")
        XCTAssertEqual(ingestion.notes, "")
        XCTAssertEqual(experience.creationDate, Date(millisecondsSince1970: 1_700_000_000_000))
        let context = PersistenceController(inMemory: true).viewContext
        try legacy.replaceJournal(in: context)
        XCTAssertEqual(try context.fetch(ShulginRating.fetchRequest()).first?.creationDate, experience.creationDate)
    }

    func testV12PreservesSingleUnitsAndAllMixtureComponents() throws {
        let json = #"""
          {"exportSource":"Android Journal",
          "customSubstances":[{"name":"Existing custom","units":"g","description":"Original"}],
          "customUnits":[
            {"id":"7","name":"Single","unit":"scoop","doseComponents":[{"substanceName":"Ingredient A","dose":10,"units":"mg"}]},
            {"id":"blend","name":"Blend","unit":"serving","doseComponents":[
              {"customUnitId":7,"dose":2},{"substanceName":"Ingredient B","amount":5,"unit":"mg"},
              {"substanceName":"Ingredient C","units":"mg"}]}],
          "experiences":[{"title":"Example","text":"","creationDate":1700000000000,"ingestions":[
            {"time":1700000000000,"administrationRoute":"ORAL","dose":2,"customUnitId":"7"},
            {"time":1700000001000,"administrationRoute":"ORAL","dose":3,"customUnitId":"blend"}]}]}
          """#
        for source in ["Android Journal", "iOS Journal"] {
            let journal = try JournalFile.read(Data(json.replacingOccurrences(of: "Android Journal", with: source).utf8))
            XCTAssertEqual(journal.customSubstances.map(\.name), ["Existing custom"])
            XCTAssertEqual(journal.customUnits.map(\.name), ["Single"])
            XCTAssertEqual(journal.formulations.first?.components.map(\.substanceName), ["Ingredient A", "Ingredient B", "Ingredient C"])
            let context = PersistenceController(inMemory: true).viewContext
            try journal.replaceJournal(in: context)
            let ingestions = try context.fetch(Ingestion.fetchRequest())
            XCTAssertEqual(ingestions.count, 4)
            let single = try XCTUnwrap(ingestions.first { $0.customUnit != nil })
            XCTAssertEqual(single.customUnit?.name, "Single")
            XCTAssertEqual(single.pureSubstanceDose, 20)
            let blend = Dictionary(uniqueKeysWithValues: ingestions.filter { $0.formulation != nil }.map { ($0.substanceNameUnwrapped, $0) })
            XCTAssertEqual(blend["Ingredient A"]?.doseUnwrapped, 60)
            XCTAssertEqual(blend["Ingredient B"]?.doseUnwrapped, 15)
            XCTAssertNil(blend["Ingredient C"]?.doseUnwrapped)
            XCTAssertEqual(blend["Ingredient C"]?.formulationAmount, 3)
        }
    }

    func testV12RejectsUnresolvableUnitReferences() {
        let json = #"""
          {"exportSource":"iOS Journal","experiences":[],"customUnits":[
            {"id":7,"name":"Cycle","doseComponents":[{"customUnitId":"7","dose":1}]}]}
          """#
        XCTAssertThrowsError(try JournalFile.read(Data(json.utf8)))
        XCTAssertThrowsError(try JournalFile.read(Data(#"{"exportSource":"Other Journal","experiences":[]}"#.utf8)))
    }

    func testFailedJournalReplacementKeepsSavedEntries() throws {
        let persistence = PersistenceController(inMemory: true)
        let savedContext = persistence.viewContext
        _ = Experience.create(at: .now, title: "Original", in: savedContext)
        try savedContext.save()

        let importContext = FailingImportContext(concurrencyType: .mainQueueConcurrencyType)
        importContext.persistentStoreCoordinator = persistence.container.persistentStoreCoordinator
        let sourceContext = PersistenceController(inMemory: true).viewContext
        let replacement = Experience.create(at: .now, title: "Replacement", in: sourceContext)
        let journal = JournalFile(experiences: [replacement], customSubstances: [], customUnits: [])

        XCTAssertThrowsError(try journal.replaceJournal(in: importContext))
        XCTAssertFalse(importContext.hasChanges)
        XCTAssertEqual(try importContext.fetch(Experience.fetchRequest()).map(\.title), ["Original"])
    }

    private final class FailingImportContext: NSManagedObjectContext, @unchecked Sendable {
        override func save() throws {
            if !insertedObjects.isEmpty {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try super.save()
        }
    }

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
