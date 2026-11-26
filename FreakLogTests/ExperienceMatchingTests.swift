import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class ExperienceMatchingTests: XCTestCase {
    func testExperienceMatchingUsesRecordedAndDraftEndTimes() throws {
        let context = try makeContext()
        let hour: TimeInterval = 3_600
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(72 * hour)
        let longer = Experience(context: context)
        longer.sortDate = start
        let rangedIngestion = Ingestion(context: context)
        rangedIngestion.time = start
        rangedIngestion.endTime = end
        rangedIngestion.experience = longer

        let later = Experience(context: context)
        later.sortDate = end.addingTimeInterval(5 * hour)
        let distant = Experience(context: context)
        distant.sortDate = end.addingTimeInterval(-96 * hour)
        try context.save()

        let candidates = try context.fetch(PersistenceController.experiencesRequest(near: end))
        XCTAssertEqual(candidates, [later, longer])
        XCTAssertEqual(ExperienceLogic.closestExperience(from: candidates, to: end), longer)
        let overlapping = end.addingTimeInterval(4 * hour)...end.addingTimeInterval(6 * hour)
        XCTAssertEqual(ExperienceLogic.closestExperience(from: candidates, to: overlapping), later)

        let future = end.addingTimeInterval(100 * hour)
        XCTAssertTrue(try context.fetch(PersistenceController.experiencesRequest(near: future)).isEmpty)
        XCTAssertNil(ExperienceLogic.closestExperience(from: candidates, to: future))
    }

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
