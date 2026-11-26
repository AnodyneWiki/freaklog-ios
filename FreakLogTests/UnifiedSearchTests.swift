import CoreData
@testable import FreakLog
import XCTest

final class UnifiedSearchTests: XCTestCase {
    func testSearchTermsCombineFieldsAndKeepQuotedPhrases() {
        XCTAssertEqual(
            SearchLogic.unifiedTerms(in: #" caffeine "next morning" Alex caffeine "#),
            ["caffeine", "next morning", "Alex"]
        )
        XCTAssertTrue(SearchLogic.matches(terms: ["coffee", "cafe"], fields: ["Coffee", "Café visit"]))
        XCTAssertFalse(SearchLogic.matches(terms: ["coffee", "cafe visit"], fields: ["Coffee", "Cafe", "Visit"]))
        XCTAssertTrue(SearchLogic.substanceName("1P-LSD", matches: "1PLSD"))
    }

    @MainActor
    func testCompoundJournalSearchWorksInSQLiteStore() throws {
        let context = try makeContext()
        let favorite = Experience(context: context)
        favorite.title = "Morning"
        favorite.sortDate = .now
        favorite.isFavorite = true

        let caffeine = Ingestion(context: context)
        caffeine.experience = favorite
        caffeine.substanceName = "Caffeine"
        caffeine.consumerName = "Alex"
        caffeine.time = .now

        let tea = CustomSubstance(context: context)
        tea.name = "Personal tea"
        tea.explanation = "special blend"
        let teaIngestion = Ingestion(context: context)
        teaIngestion.experience = favorite
        teaIngestion.substanceName = "Personal tea"
        teaIngestion.time = .now

        let note = TimedNote(context: context)
        note.experience = favorite
        note.note = "Headache went away"

        let rating = ShulginRating(context: context)
        rating.experience = favorite
        rating.option = ShulginRatingOption.twoPlus.rawValue

        let other = Experience(context: context)
        other.title = "Headache"
        other.sortDate = .now
        let otherIngestion = Ingestion(context: context)
        otherIngestion.experience = other
        otherIngestion.substanceName = "Caffeine"
        otherIngestion.consumerName = "Alex"
        otherIngestion.time = .now
        try context.save()

        let query = UnifiedJournalQuery(
            terms: ["caffeine", "special blend", "headache", "++"], customSubstances: [tea], favoritesOnly: true
        )
        XCTAssertEqual(try context.fetch(query.experiencesRequest(limit: 10)), [favorite])
        XCTAssertTrue(try context.fetch(query.ingestionsRequest(limit: 10)).isEmpty)

        let ingestionQuery = UnifiedJournalQuery(terms: ["caffeine", "alex"], customSubstances: [], favoritesOnly: true)
        XCTAssertEqual(try context.fetch(ingestionQuery.ingestionsRequest(limit: 10)), [caffeine])
    }

    @MainActor
    func testFormulationFilterAppliesToTheIngestionMatchingATerm() throws {
        let context = try makeContext()
        let experience = Experience(context: context)
        experience.title = "Morning"
        experience.sortDate = .now
        let formulation = Formulation(context: context)
        formulation.name = "House Blend"

        let component = Ingestion(context: context)
        component.experience = experience
        component.time = .now
        component.substanceName = "Caffeine"
        component.formulation = formulation

        let standalone = Ingestion(context: context)
        standalone.experience = experience
        standalone.time = .now
        standalone.substanceName = "Melatonin"
        try context.save()

        let matching = UnifiedJournalQuery(
            terms: ["house blend", "caffeine"], customSubstances: [], favoritesOnly: false,
            ingestionKind: .formulationComponent
        )
        XCTAssertEqual(try context.fetch(matching.experiencesRequest(limit: 10)), [experience])
        XCTAssertEqual(try context.fetch(matching.ingestionsRequest(limit: 10)), [component])

        let wrongKind = UnifiedJournalQuery(
            terms: ["caffeine"], customSubstances: [], favoritesOnly: false, ingestionKind: .standalone
        )
        XCTAssertTrue(try context.fetch(wrongKind.experiencesRequest(limit: 10)).isEmpty)
        XCTAssertTrue(try context.fetch(wrongKind.ingestionsRequest(limit: 10)).isEmpty)

        let searchByKindOnly = UnifiedJournalQuery(
            terms: [], customSubstances: [], favoritesOnly: false, ingestionKind: .standalone
        )
        XCTAssertEqual(try context.fetch(searchByKindOnly.experiencesRequest(limit: 10)), [experience])
        XCTAssertEqual(try context.fetch(searchByKindOnly.ingestionsRequest(limit: 10)), [standalone])
    }

    @MainActor
    private func makeContext() throws -> NSManagedObjectContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let modelURL = try XCTUnwrap(Bundle.main.url(forResource: "Main", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(
            type: .sqlite, at: directory.appendingPathComponent("test.sqlite"), options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
