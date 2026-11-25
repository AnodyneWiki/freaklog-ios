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
