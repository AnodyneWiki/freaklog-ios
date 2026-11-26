import CoreData
import UIKit
import XCTest
@testable import FreakLog

@MainActor
final class InventoryLabReportTests: XCTestCase {
    func testValidPDFCanBeAttachedReplacedAndRemovedWithoutAffectingOtherContainers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = InventoryLabReportStore(directory: directory.appendingPathComponent("Reports", isDirectory: true))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Report.pdf")
        let rendered = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
            .pdfData { $0.beginPage() }
        try rendered.write(to: url)
        let pdf = try InventoryLabReportStore.readPDF(at: url)
        XCTAssertEqual(pdf, rendered)

        let report = InventoryLabReport(filename: "Report.pdf", stockFingerprint: "stock", data: pdf)
        let replacement = InventoryLabReport(filename: "Replacement.pdf", stockFingerprint: "new stock", data: pdf)
        try store.attach(report, to: "first")
        try store.attach(report, to: "second")
        try store.attach(replacement, to: "first")
        XCTAssertEqual(try store.report(for: "first")?.id, replacement.id)
        XCTAssertEqual(try store.report(for: "second")?.id, report.id)
        try store.remove(from: "first")
        XCTAssertNil(try store.report(for: "first"))
        XCTAssertEqual(try store.report(for: "second")?.data, pdf)
        try store.removeAll()
        XCTAssertNil(try store.report(for: "second"))
    }

    func testPDFImportRejectsInvalidAndOversizeFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("This is not a PDF.".utf8).write(to: url)
        XCTAssertThrowsError(try InventoryLabReportStore.readPDF(at: url)) { error in
            XCTAssertEqual(error as? InventoryLabReportStore.Failure, .invalidPDF)
        }

        try Data(count: InventoryLabReportStore.maxPDFSize + 1).write(to: url)
        XCTAssertThrowsError(try InventoryLabReportStore.readPDF(at: url)) { error in
            XCTAssertEqual(error as? InventoryLabReportStore.Failure, .tooLarge)
        }
    }

    func testCountingUnitRenameKeepsLinkedStockAndHistory() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let product = CustomUnit(context: context)
        product.unit = "pill"
        let linked = StockContainer(context: context)
        linked.customUnit = product
        linked.unit = "pill"
        let standalone = StockContainer(context: context)
        standalone.unit = "pill"
        let differentMeasurement = StockContainer(context: context)
        differentMeasurement.customUnit = product
        differentMeasurement.unit = "bottle"
        try Inventory.stage(.opening, quantity: 10, in: linked)

        Inventory.renameCountingUnit(of: product, to: "tablet")
        product.unit = "tablet"
        try context.save()

        XCTAssertEqual(linked.unit, "tablet")
        XCTAssertEqual(linked.remaining, 10)
        XCTAssertEqual(standalone.unit, "pill")
        XCTAssertEqual(differentMeasurement.unit, "bottle")
    }

    func testRestoringBackupKeepsTheLocalLabReportLink() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let unit = CustomUnit(context: context)
        unit.substanceName = "Example"
        unit.administrationRoute = "oral"
        unit.originalUnit = "mg"
        unit.dose = 5
        let container = StockContainer(context: context)
        container.name = "Sample"
        container.customUnit = unit
        container.unit = "tablets"
        container.labReportID = UUID()
        try Inventory.stage(.opening, quantity: 10, in: container, at: Date(timeIntervalSince1970: 1_795_277_618.1234567))
        try context.save()

        let identifier = container.labReportContainerID
        let objectID = container.objectID
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = InventoryLabReportStore(directory: directory)
        defer { try? store.removeAll() }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { $0.beginPage() }
        let report = InventoryLabReport(filename: "Private.pdf", stockFingerprint: container.labReportStockFingerprint, data: pdf)
        try store.attach(report, to: identifier)
        let backup = try JournalBackup(context: context, appVersion: "1")
        let encoded = try backup.fileData()
        XCTAssertNil(encoded.range(of: Data(report.filename.utf8)))
        XCTAssertNil(encoded.range(of: Data(pdf.base64EncodedString().utf8)))

        let restoredBackup = try XCTUnwrap(JournalBackup.read(encoded))
        try restoredBackup.restore(into: context)
        try context.save()
        let restored = try XCTUnwrap(context.fetch(StockContainer.allRequest()).first)
        XCTAssertNotEqual(restored.objectID, objectID)
        XCTAssertEqual(restored.labReportContainerID, identifier)
        let restoredReport = try XCTUnwrap(store.report(for: restored.labReportContainerID))
        XCTAssertTrue(restored.isLabReportCurrent(restoredReport))
    }

    func testNewStockInvalidatesAnExistingReportAndUsingStockKeepsItCurrent() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let container = StockContainer(context: context)
        container.productName = "Sample"
        container.unit = "tablets"
        try Inventory.stage(.opening, quantity: 10, in: container)
        let originalStock = container.labReportStockFingerprint

        try Inventory.stage(.use, quantity: -1, in: container)
        try Inventory.stage(.transferOut, quantity: -2, in: container)
        XCTAssertEqual(container.labReportStockFingerprint, originalStock)

        try Inventory.stage(.restock, quantity: 3, in: container)
        let restocked = container.labReportStockFingerprint
        XCTAssertNotEqual(restocked, originalStock)

        try Inventory.stage(.transferIn, quantity: 1, in: container)
        XCTAssertNotEqual(container.labReportStockFingerprint, restocked)
    }
}
