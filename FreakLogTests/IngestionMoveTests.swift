import CoreData
import XCTest
@testable import FreakLog

final class IngestionMoveTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testSplitAndUndoPreserveIngestionLinksAndExperienceNotes() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let source = Experience.create(at: start, title: "Source", in: context)
        let earlier = addIngestion(at: start, to: source, in: context)
        let later = addIngestion(at: start.addingTimeInterval(3600), to: source, in: context)
        let change = StockChange(context: context)
        let occurrence = RoutineOccurrence(context: context)
        let note = TimedNote(context: context)
        let rating = ShulginRating(context: context)
        earlier.stockChange = change
        earlier.routineOccurrence = occurrence
        note.experience = source
        rating.experience = source
        try PersistenceController.saveJournalChanges(in: context)

        let moveContext = try persistence.journalEditContext()
        let (receipt, ingestions) = try IngestionMove.move(
            [earlier.objectID], from: source.objectID, to: .new(title: "Split"), in: moveContext
        )
        let moved = try XCTUnwrap(ingestions.first)
        let split = try XCTUnwrap(moved.experience)
        XCTAssertEqual(split.title, "Split")
        XCTAssertEqual(split.sortDate, earlier.time)
        XCTAssertEqual(moved.stockChange?.objectID, change.objectID)
        XCTAssertEqual(moved.routineOccurrence?.objectID, occurrence.objectID)
        let read = try persistence.journalEditContext()
        let sourceAfterMove = try PersistenceController.journalObject(source, in: read)
        XCTAssertEqual(sourceAfterMove.sortDate, later.time)
        XCTAssertEqual(sourceAfterMove.timedNotesSorted.first?.objectID, note.objectID)
        XCTAssertEqual(sourceAfterMove.ratingsUnwrapped.first?.objectID, rating.objectID)

        let undoContext = try persistence.journalEditContext()
        let undone = try IngestionMove.undo(receipt, in: undoContext)
        XCTAssertEqual(undone.first?.experience?.objectID, source.objectID)
        XCTAssertEqual(undone.first?.experience?.sortDate, earlier.time)
        XCTAssertEqual(undone.first?.stockChange?.objectID, change.objectID)
        XCTAssertEqual(undone.first?.routineOccurrence?.objectID, occurrence.objectID)
        XCTAssertEqual(try persistence.journalEditContext().count(for: Experience.fetchRequest()), 1)
    }

    @MainActor
    func testAWholePendingBatchMovesAndRejectsAPartialSelection() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let source = Experience.create(at: start, in: context)
        let targetDate = start.addingTimeInterval(3600)
        let target = Experience.create(at: targetDate, in: context)
        let first = addIngestion(at: start, to: source, in: context)
        let second = addIngestion(at: start, to: source, in: context)
        let batch = UUID()
        for entry in [first, second] {
            entry.isUnconfirmed = true
            entry.confirmationBatchID = batch
        }
        try PersistenceController.saveJournalChanges(in: context)

        XCTAssertThrowsError(try IngestionMove.move(
            [first.objectID], from: source.objectID, to: .existing(target.objectID),
            in: persistence.journalEditContext()
        )) { error in
            XCTAssertEqual(error as? IngestionMove.MoveError, .incompleteBatch)
        }
        let moveContext = try persistence.journalEditContext()
        let (receipt, moved) = try IngestionMove.move(
            [first.objectID, second.objectID], from: source.objectID, to: .existing(target.objectID),
            in: moveContext
        )
        XCTAssertEqual(moved.count, 2)
        XCTAssertEqual(moved.first?.pendingConfirmationEntries.count, 2)
        XCTAssertEqual(moved.first?.experience?.sortDate, start)

        let undoContext = try persistence.journalEditContext()
        let restored = try IngestionMove.undo(receipt, in: undoContext)
        XCTAssertEqual(restored.first?.pendingConfirmationEntries.count, 2)
        let afterUndo = try PersistenceController.journalObject(target, in: undoContext)
        XCTAssertEqual(afterUndo.sortDate, targetDate)
        XCTAssertTrue(afterUndo.ingestionsSorted.isEmpty)
    }

    @MainActor
    func testUndoLeavesTheBatchUntouchedWhenAnEntryWasMovedAgain() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let source = Experience.create(at: start, in: context)
        let target = Experience.create(at: start, in: context)
        let first = addIngestion(at: start, to: source, in: context)
        let second = addIngestion(at: start, to: source, in: context)
        try PersistenceController.saveJournalChanges(in: context)

        let (receipt, _) = try IngestionMove.move(
            [first.objectID, second.objectID], from: source.objectID, to: .existing(target.objectID),
            in: persistence.journalEditContext()
        )
        _ = try IngestionMove.move(
            [second.objectID], from: target.objectID, to: .new(title: "Different move"),
            in: persistence.journalEditContext()
        )
        XCTAssertThrowsError(try IngestionMove.undo(receipt, in: persistence.journalEditContext()))
        let readContext = try persistence.journalEditContext()
        let check = try PersistenceController.journalObject(first, in: readContext)
        XCTAssertEqual(check.experience?.objectID, target.objectID)
    }

    private func addIngestion(at time: Date, to experience: Experience, in context: NSManagedObjectContext) -> Ingestion {
        let ingestion = Ingestion(context: context)
        ingestion.time = time
        ingestion.experience = experience
        return ingestion
    }
}
