import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class IngestionBatchTests: XCTestCase {
    func testBatchPreservesIndividualTimesAndStockLinksInChosenExperience() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.viewContext
        let (unit, container) = try productWithStock(5, in: context)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let later = first.addingTimeInterval(3_600)
        let end = later.addingTimeInterval(900)
        let destination = Experience.create(at: later, title: "Existing", in: context)
        try context.save()

        let saved = try StagedIngestion.persist(
            [draft(at: later, end: end, amount: 2, unit: unit, stock: container),
             draft(at: first, amount: 1, unit: unit, stock: container)],
            to: destination, title: "", persistence: store
        )

        XCTAssertEqual(saved.experience.objectID, destination.objectID)
        XCTAssertEqual(saved.experience.sortDate, first)
        XCTAssertEqual(saved.ingestions.compactMap(\.time), [later, first])
        XCTAssertEqual(saved.ingestions.first?.endTime, end)
        XCTAssertNil(saved.ingestions.last?.endTime)
        XCTAssertEqual(saved.ingestions.first?.stockChange?.container?.remaining, 2)
        XCTAssertEqual(saved.ingestions.map { $0.stockChange?.quantity }, [-2, -1])
        XCTAssertNotEqual(saved.ingestions.first?.stockChange?.objectID, saved.ingestions.last?.stockChange?.objectID)
        XCTAssertEqual(saved.ingestions.first?.note, "First label")
        XCTAssertEqual(saved.ingestions.first?.consumerName, "Example")
    }

    func testInsufficientCombinedStockSavesNothingAndDraftsCanBeRetried() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.viewContext
        let (unit, container) = try productWithStock(3, in: context)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let earlyDraft = draft(at: first, amount: 2, unit: unit, stock: container)
        var laterDraft = draft(at: first.addingTimeInterval(3_600), amount: 2, unit: unit, stock: container)

        XCTAssertThrowsError(
            try StagedIngestion.persist([earlyDraft, laterDraft], to: nil, title: "Batch", persistence: store)
        ) { error in
            XCTAssertEqual(error as? InventoryError, .insufficientStock)
        }
        let freshContext = try store.journalEditContext()
        XCTAssertEqual(try freshContext.count(for: Ingestion.fetchRequest()), 0)
        XCTAssertEqual(try freshContext.count(for: Experience.fetchRequest()), 0)
        XCTAssertEqual(try freshContext.count(for: SubstanceCompanion.fetchRequest()), 0)
        let unchanged = try PersistenceController.journalObject(container, in: freshContext)
        XCTAssertEqual(unchanged.remaining, 3)

        laterDraft.stockContainerID = nil
        let saved = try StagedIngestion.persist(
            [earlyDraft, laterDraft], to: nil, title: "Batch", persistence: store
        )
        XCTAssertEqual(saved.ingestions.count, 2)
        XCTAssertEqual(saved.experience.title, "Batch")
        XCTAssertEqual(saved.ingestions.first?.stockChange?.container?.remaining, 1)
        XCTAssertNil(saved.ingestions.last?.stockChange)
    }

    func testDeletionRequestUsesEntryIdentityAndRejectsChangedBatchMembership() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.viewContext
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let experience = Experience.create(at: time, in: context)
        let batchID = UUID()
        let entries = try (0..<3).map { index -> Ingestion in
            let entity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Ingestion", in: context))
            let entry = Ingestion(entity: entity, insertInto: context)
            entry.substanceName = "Example Product"
            entry.time = time.addingTimeInterval(Double(index))
            entry.experience = experience
            entry.isUnconfirmed = index < 2
            entry.confirmationBatchID = index < 2 ? batchID : nil
            return entry
        }
        try context.save()

        let single = IngestionDeletion.Request(entries[2])
        let batch = IngestionDeletion.Request(entries[0])
        let freshContext = try store.journalEditContext()
        XCTAssertEqual(try single.resolve(in: freshContext).map(\.objectID), [entries[2].objectID])
        XCTAssertEqual(Set(try batch.resolve(in: freshContext).map(\.objectID)), Set(entries.prefix(2).map(\.objectID)))

        entries[2].isUnconfirmed = true
        entries[2].confirmationBatchID = batchID
        try context.save()
        let changedContext = try store.journalEditContext()
        XCTAssertThrowsError(try single.resolve(in: changedContext))
        XCTAssertThrowsError(try batch.resolve(in: changedContext))
    }

    private func productWithStock(
        _ count: Double, in context: NSManagedObjectContext
    ) throws -> (CustomUnit, StockContainer) {
        let unit = CustomUnit(context: context)
        unit.name = "Example tablet"
        unit.unit = "tablet"
        unit.originalUnit = "mg"
        unit.substanceName = "Example Product"
        unit.administrationRoute = "oral"
        unit.dose = 10
        let container = StockContainer(context: context)
        container.customUnit = unit
        container.unit = "tablet"
        try Inventory.stage(.opening, quantity: count, in: container)
        try context.save()
        return (unit, container)
    }

    private func draft(
        at date: Date, end: Date? = nil, amount: Double, unit: CustomUnit, stock: StockContainer
    ) -> StagedIngestion {
        StagedIngestion(
            arguments: [
                FinishIngestionScreenArguments(
                    substanceName: unit.substanceNameUnwrapped,
                    administrationRoute: .oral,
                    dose: amount,
                    units: unit.unitUnwrapped,
                    isEstimate: false,
                    estimatedDoseStandardDeviation: nil,
                    customUnit: unit
                )
            ],
            time: date, endTime: end, note: "First label", consumer: "Example", location: nil,
            sites: AdministrationSiteSelection(), colors: [:], isUnconfirmed: false,
            stockContainerID: stock.objectID, webhookPresetIDs: []
        )
    }
}
