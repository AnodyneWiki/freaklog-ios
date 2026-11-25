import CoreData
@testable import FreakLog
import XCTest

@MainActor
final class JournalFileTests: XCTestCase {
    func testAbortedReplacementLeavesJournalIntactAfterAnotherSave() throws {
        enum TestError: Error { case abort }

        let persistence = PersistenceController(inMemory: true)
        let viewContext = persistence.viewContext
        let original = Experience.create(at: .now, title: "Original", in: viewContext)
        try viewContext.save()

        do {
            let edit = try persistence.journalEditContext()
            XCTAssertThrowsError(try SettingsScreen.ViewModel.replaceJournal(in: edit, removePublishedCopies: true) {
                try PersistenceController.stageJournalDeletion(in: edit)
                throw TestError.abort
            })
        }

        original.title = "Edited after failure"
        try viewContext.save()
        let check = try persistence.journalEditContext()
        XCTAssertEqual(try check.fetch(Experience.fetchRequest()).map(\.title), ["Edited after failure"])
    }

    func testReplacementQueuesOnlyDiscardedPublicationsWhenSelected() throws {
        for removePublishedCopies in [true, false] {
            let persistence = PersistenceController(inMemory: true)
            let context = persistence.viewContext
            let oldID = UUID()
            let retainedID = UUID()
            let url = "https://example.invalid/webhooks/test"

            func insert(ingestionID: UUID, messageID: String, in context: NSManagedObjectContext) {
                let ingestion = Ingestion(context: context)
                ingestion.identifier = ingestionID
                let message = WebhookMessage(context: context)
                message.ingestion = ingestion
                message.messageId = messageID
                message.destinationURL = url
            }

            insert(ingestionID: oldID, messageID: "discarded", in: context)
            insert(ingestionID: retainedID, messageID: "retained", in: context)
            try context.save()

            let edit = try persistence.journalEditContext()
            let removed = try SettingsScreen.ViewModel.replaceJournal(in: edit, removePublishedCopies: removePublishedCopies) {
                try PersistenceController.stageJournalDeletion(in: edit)
                insert(ingestionID: retainedID, messageID: "retained", in: edit)
            }

            let check = try persistence.journalEditContext()
            XCTAssertEqual(removed, removePublishedCopies ? [oldID] : [])
            XCTAssertEqual(try check.fetch(WebhookDeletion.fetchRequest()).compactMap(\.messageId),
                           removePublishedCopies ? ["discarded"] : [])
        }
    }

    func testIsolatedDeletionUpdatesStoredExperienceSortDate() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let firstTime = Date(timeIntervalSince1970: 1_700_000_000)
        let secondTime = firstTime.addingTimeInterval(3_600)
        let experience = Experience.create(at: firstTime, in: context)
        let first = Ingestion(context: context)
        first.time = firstTime
        first.experience = experience
        let second = Ingestion(context: context)
        second.time = secondTime
        second.experience = experience
        try context.save()

        let edit = try persistence.journalEditContext()
        edit.delete(try PersistenceController.journalObject(first, in: edit))
        try PersistenceController.saveJournalChanges(in: edit)

        let check = try persistence.journalEditContext()
        XCTAssertEqual(try PersistenceController.journalObject(experience, in: check).sortDate, secondTime)
    }

    func testJournalImportRejectsAnEmptyUnidentifiedFile() throws {
        let decoder = JSONDecoder()
        for json in ["{}", #"{"customUnits":[]}"#, #"{"experiences":null}"#, #"{"experiences":{}}"#] {
            XCTAssertThrowsError(try decoder.decode(JournalFile.self, from: Data(json.utf8)), json)
        }
        let emptyJournal = try decoder.decode(JournalFile.self, from: Data(#"{"experiences":[]}"#.utf8))
        XCTAssertTrue(emptyJournal.experiences.isEmpty)
        let review = SettingsScreen.ImportReview(filename: "Journal.json", contents: .journal(emptyJournal))
        XCTAssertTrue(review.isEmptyJournal)
        XCTAssertNil(review.dateRange)
        XCTAssertThrowsError(try JournalFile.read(Data("{}".utf8))) {
            XCTAssertEqual($0 as? JournalFileError, .noJournalData)
        }
    }

    func testImportReviewUsesLoggedTimesAndExperienceFallbackDates() throws {
        let data = Data(#"""
            {"experiences":[
              {"title":"Timed","text":"","creationDate":1800000000000,"sortDate":1500000000000,
              "ingestions":[{"substanceName":"Example","time":1700000000000,"endTime":1700003600000,
              "administrationRoute":"ORAL","isDoseAnEstimate":false}],
              "timedNotes":[{"time":1600000000000,"creationDate":1800000000000,"note":"Example",
              "color":"MINT","isPartOfTimeline":true}],
              "ratings":[{"option":"twoPlus","time":1700001800000}]},
              {"title":"Untimed","text":"","creationDate":1800000000000,"sortDate":1750000000000}
            ]}
            """#.utf8)
        let journal = try JournalFile.read(data)
        let review = SettingsScreen.ImportReview(filename: "Journal.json", contents: .journal(journal))
        XCTAssertFalse(review.isEmptyJournal)
        XCTAssertEqual(review.dateRange,
                       Date(millisecondsSince1970: 1_600_000_000_000)...Date(millisecondsSince1970: 1_750_000_000_000))
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

    func testRejectsDuplicateAndDanglingReferenceIDs() {
        let unit = #"{"id":7,"name":"Spoon","substanceName":"Example","creationDate":1700000000000,"administrationRoute":"ORAL","isEstimate":false,"isArchived":false,"unit":"spoon","originalUnit":"mg","note":""}"#
        let formulation = #"{"id":"blend","name":"Blend","creationDate":1700000000000,"note":"","components":[]}"#
        let cases: [(String, String, String, JournalFileError)] = [
            ("[\(unit),\(unit)]", "[]", "", .duplicateCustomUnit(7)),
            ("[]", "[\(formulation),\(formulation)]", "", .duplicateFormulation("blend")),
            ("[\(unit)]", "[]", #","customUnitId":8"#, .missingCustomUnit("8")),
            ("[]", "[\(formulation)]", #","formulationId":"missing","formulationName":"Blend""#, .missingFormulation("missing")),
        ]
        for (units, formulations, reference, expected) in cases {
            let json = """
                {"customUnits":\(units),"formulations":\(formulations),"experiences":[
                  {"title":"Example","text":"","creationDate":1700000000000,"ingestions":[
                    {"substanceName":"Example","time":1700000000000,"administrationRoute":"ORAL","isDoseAnEstimate":false\(reference)}]}]}
                """
            XCTAssertThrowsError(try JournalFile.read(Data(json.utf8))) { error in
                XCTAssertEqual(error as? JournalFileError, expected)
            }
        }
    }

    func testExportRejectsRelationshipsOmittedFromTheFile() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let experience = Experience.create(at: .now, title: "Example", in: context)
        let ingestion = Ingestion(context: context)
        ingestion.experience = experience
        let unit = CustomUnit(context: context)
        unit.idForAndroid = 7
        ingestion.customUnit = unit
        XCTAssertThrowsError(try JournalFile(experiences: [experience], customSubstances: [], customUnits: [])) { error in
            XCTAssertEqual(error as? JournalFileError, .missingCustomUnit("7"))
        }
        let formulation = Formulation(context: context)
        formulation.name = "Blend"
        ingestion.formulation = formulation
        XCTAssertThrowsError(try JournalFile(experiences: [experience], customSubstances: [], customUnits: [unit])) { error in
            XCTAssertEqual(error as? JournalFileError, .missingFormulation("Blend"))
        }
    }

    func testExportAssignsFileLocalIDsToCollidingUnits() throws {
        let source = PersistenceController(inMemory: true).viewContext
        let experience = Experience.create(at: .now, title: "Example", in: source)
        let ids: [Int32] = [0, 0, 1, 7, 7, -1]
        let units = ids.enumerated().map { index, id in
            let unit = CustomUnit(context: source)
            unit.idForAndroid = id
            unit.name = "Unit \(index)"
            unit.substanceName = "Example"
            let ingestion = Ingestion(context: source)
            ingestion.substanceName = "Example"
            ingestion.time = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            ingestion.note = unit.name
            ingestion.customUnit = unit
            ingestion.experience = experience
            return unit
        }
        let file = try JournalFile(experiences: [experience], customSubstances: [], customUnits: units)
        XCTAssertEqual(file.customUnits.map(\.id), [0, 2, 1, 7, 3, -1])
        XCTAssertEqual(units.map(\.idForAndroid), ids)

        let decoded = try JournalFile.read(JSONEncoder().encode(file))
        let target = PersistenceController(inMemory: true).viewContext
        decoded.insert(into: target)
        let ingestions = try target.fetch(Ingestion.fetchRequest())
        XCTAssertEqual(ingestions.count, units.count)
        for ingestion in ingestions {
            XCTAssertEqual(ingestion.customUnit?.name, ingestion.note)
        }
    }

    func testPortableLocationRoundTripDistinguishesZeroFromMissing() throws {
        let json = #"""
            {"experiences":[{"title":"Example","text":"","creationDate":1700000000000,"ingestions":[
              {"substanceName":"Example","time":1700000000000,"administrationRoute":"ORAL","isDoseAnEstimate":false,
              "location":{"name":"Equator","latitude":0}}
            ]}]}
            """#
        let context = PersistenceController(inMemory: true).viewContext
        try JournalFile.read(Data(json.utf8)).replaceJournal(in: context)
        let experience = try XCTUnwrap(context.fetch(Experience.fetchRequest()).first)
        let exported = try JournalFile(experiences: [experience], customSubstances: [], customUnits: [])
        let decoded = try JournalFile.read(JSONEncoder().encode(exported))
        let location = try XCTUnwrap(decoded.experiences.first?.ingestions.first?.location)
        XCTAssertEqual(location.latitude, 0)
        XCTAssertNil(location.longitude)
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
        let journal = try JournalFile(experiences: [replacement], customSubstances: [], customUnits: [])

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
        ingestion.isHiddenInTimeline = true
        ingestion.stomachFullness = "halfFull"
        let companion = SubstanceCompanion(context: source)
        companion.substanceName = "Ketamine"
        companion.isHiddenInTimeline = true
        ingestion.substanceCompanion = companion
        let rating = ShulginRating(context: source)
        rating.creationDate = Date(timeIntervalSince1970: 6_000)
        rating.option = ShulginRatingOption.twoPlus.rawValue
        rating.experience = experience
        rating.isHiddenInTimeline = true
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

        let file = try JournalFile(
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
        XCTAssertEqual(importedExperience.ratingsUnwrapped.first?.isHiddenInTimeline, true)
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
        XCTAssertTrue(importedIngestion.isHiddenInTimeline)
        XCTAssertEqual(importedIngestion.stomachFullness, "halfFull")
        XCTAssertEqual(importedIngestion.substanceCompanion?.isHiddenInTimeline, true)
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

    func testSimilarSubstanceMergePreservesRecordedAmountsAndMovesLinkedData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let target = CustomSubstance(context: context)
        target.name = "Example Product"
        target.units = "mg"
        let duplicate = CustomSubstance(context: context)
        duplicate.name = "Example Product A"
        duplicate.units = "cups"

        let route = CustomRoa(context: context)
        route.customSubstance = duplicate
        route.administrationRoute = AdministrationRoute.oral.rawValue
        route.commonDose = 5
        let container = CustomUnit(context: context)
        container.substanceName = duplicate.name
        let companion = SubstanceCompanion(context: context)
        companion.substanceName = duplicate.name
        companion.isHiddenInTimeline = true
        let ingestion = Ingestion(context: context)
        ingestion.substanceName = duplicate.name
        ingestion.dose = 8
        ingestion.units = "cups"
        ingestion.customUnit = container
        ingestion.substanceCompanion = companion
        let override = SubstanceOverride(context: context)
        override.substanceName = duplicate.name
        override.personalTags = PersonalSubstanceTags(["Routine"], primary: "Routine")
        try context.save()

        XCTAssertNotNil(SimilarSubstanceNames.distance(target.nameUnwrapped, duplicate.nameUnwrapped))
        let pair = SimilarCustomSubstancePair(first: target, second: duplicate)
        let records = try CustomSubstanceMergeRecords.load(pair, in: context)
        XCTAssertEqual(records.preview.ingestionCount, 1)
        XCTAssertEqual(records.preview.unitCount, 1)
        _ = try records.merge(selection: ["name": 0, "visibility": 1], in: context)

        XCTAssertEqual(try context.fetch(PersistenceController.customSubstancesRequest()).map(\.nameUnwrapped), ["Example Product"])
        XCTAssertEqual(ingestion.substanceName, target.name)
        XCTAssertEqual(ingestion.dose, 8)
        XCTAssertEqual(ingestion.units, "cups")
        XCTAssertEqual(ingestion.customUnit, container)
        XCTAssertEqual(container.substanceName, target.name)
        XCTAssertTrue(ingestion.substanceCompanion?.isHiddenInTimeline == true)
        let savedRoute = try XCTUnwrap(context.fetch(PersistenceController.customRoasRequest(for: target.nameUnwrapped)).first)
        XCTAssertEqual(savedRoute.customSubstance, target)
        XCTAssertEqual(savedRoute.doseUnits, "cups")

        let overrides = try context.fetch(PersistenceController.substanceOverridesRequest(for: target.nameUnwrapped))
        let overridesFile = SubstanceDataOverrideCodable.grouped([], overrides: overrides)
        let data = try JSONEncoder().encode(overridesFile)
        let decoded = try JSONDecoder().decode([SubstanceDataOverrideCodable].self, from: data)
        let tags = try XCTUnwrap(decoded.first?.personalTags)
        XCTAssertEqual(tags.primary, "Routine")
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
