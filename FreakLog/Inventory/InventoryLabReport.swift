import CoreData
import CryptoKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct InventoryLabReport: Codable, Identifiable, Sendable {
    let id: UUID
    let filename: String
    let attachedAt: Date
    let stockFingerprint: String
    let data: Data

    init(filename: String, stockFingerprint: String, data: Data) {
        self.id = UUID()
        self.filename = filename
        self.attachedAt = .now
        self.stockFingerprint = stockFingerprint
        self.data = data
    }
}

struct InventoryLabReportStore: Sendable {
    static let local = Self(directory: URL.applicationSupportDirectory.appendingPathComponent("Inventory Lab Reports", isDirectory: true))
    static let maxPDFSize = 10 * 1024 * 1024
    let directory: URL

    func report(for containerID: String) throws -> InventoryLabReport? {
        let url = file(for: containerID)
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(InventoryLabReport.self, from: data)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    static func load(for containerID: String, legacyID: String) async throws -> InventoryLabReport? {
        try await Task.detached(priority: .utility) {
            if let report = try local.report(for: containerID) { return report }
            if legacyID == containerID { return nil }
            return try local.report(for: legacyID)
        }.value
    }

    func attach(_ report: InventoryLabReport, to containerID: String) throws {
        guard !report.data.isEmpty else { throw Failure.invalidPDF }
        guard report.data.count <= Self.maxPDFSize else { throw Failure.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(report).write(to: file(for: containerID), options: [.atomic, .completeFileProtection])
    }

    func remove(from containerID: String) throws {
        try Self.removeIfPresent(file(for: containerID))
    }

    func removeAll() throws {
        try Self.removeIfPresent(directory)
    }

    static func readPDF(at url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var data = Data()
        var coordinationError: NSError?
        var readerError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let file = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? file.close() }
                data = try file.read(upToCount: maxPDFSize + 1) ?? Data()
            } catch {
                readerError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let readerError { throw readerError }
        guard data.count <= maxPDFSize else { throw Failure.tooLarge }
        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
            throw Failure.invalidPDF
        }
        return data
    }

    private func file(for containerID: String) -> URL {
        let key = SHA256.hash(data: Data(containerID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key, isDirectory: false).appendingPathExtension("plist")
    }

    private static func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }

    enum Failure: LocalizedError {
        case tooLarge, invalidPDF, containerChanged

        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "Choose a PDF no larger than 10 MB.")
            case .invalidPDF: String(localized: "Choose an unlocked PDF with at least one page.")
            case .containerChanged: String(localized: "The container or its stock changed. Open the container and try again.")
            }
        }
    }
}

extension StockContainer {
    var legacyLabReportContainerID: String { objectID.uriRepresentation().absoluteString }

    var labReportContainerID: String { labReportID?.uuidString ?? legacyLabReportContainerID }

    func isLabReportCurrent(_ report: InventoryLabReport) -> Bool {
        if report.stockFingerprint.hasPrefix("v2:") {
            return report.stockFingerprint == labReportStockFingerprint
        }
        return report.stockFingerprint == legacyLabReportStockFingerprint
    }

    // Added or returned stock may be from a different batch. Ordinary use and outgoing transfers
    // do not change the fingerprint of the material remaining in the container.
    var labReportStockFingerprint: String {
        var fields: [String]
        if let customUnit {
            fields = [
                "custom unit", customUnit.substanceName ?? "", customUnit.administrationRoute ?? "",
                customUnit.originalUnit ?? "", String(customUnit.dose.bitPattern),
            ]
        } else if let formulation {
            fields = ["formulation"] + formulation.componentsUnwrapped.map { component in
                Self.fingerprint([
                    component.substanceName ?? "", component.administrationRoute ?? "",
                    component.units ?? "", String(component.dose.bitPattern),
                ])
            }.sorted()
        } else {
            fields = ["standalone", productName ?? "", unit ?? ""]
        }
        fields += materialChanges.map { change in
            Self.fingerprint([
                change.kind ?? "", change.date.map(BackupDate.string) ?? "", String(change.quantity.bitPattern),
            ])
        }.sorted()
        return "v2:" + Self.fingerprint(fields)
    }

    private var materialChanges: [StockChange] {
        stockChanges.filter {
            $0.kind == StockChangeKind.opening.rawValue || $0.quantity > 0 || $0.isReversedUse
        }
    }

    private var legacyLabReportStockFingerprint: String {
        var fields = [
            productName ?? "",
            unit ?? "",
            customUnit?.objectID.uriRepresentation().absoluteString ?? "",
            formulation?.objectID.uriRepresentation().absoluteString ?? ""
        ]
        fields += materialChanges.map { change in
            "\(change.kind ?? ""):\(change.date?.timeIntervalSinceReferenceDate.bitPattern ?? 0):\(change.quantity.bitPattern)"
        }.sorted()
        return Self.fingerprint(fields)
    }

    private static func fingerprint(_ fields: [String]) -> String {
        let data = Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct InventoryLabReportManagementRows: View {
    @ObservedObject var container: StockContainer

    @State private var report: InventoryLabReport?
    @State private var preview: InventoryLabReport?
    @State private var choosingPDF = false
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var confirmsRemoval = false
    @State private var errorMessage: String?

    private var isCurrent: Bool { report.map(container.isLabReportCurrent) ?? false }

    var body: some View {
        Button {
            if let report { preview = report } else { choosingPDF = true }
        } label: {
            if isLoading || isImporting {
                ProgressView(isImporting ? "Attaching Report…" : "Loading Report…")
            } else if let report {
                InventoryLabReportLabel(filename: report.filename)
            } else {
                Label("Attach Lab Report", systemImage: "paperclip")
            }
        }
        .disabled(isLoading || isImporting)
        .task(id: container.labReportContainerID) { await loadReport() }
        .sheet(item: $preview) { report in
            InventoryLabReportPreview(report: report)
        }
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): importPDF(url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { errorMessage = error.localizedDescription }
            }
        }
        if report != nil {
            if !isCurrent {
                Text("Stock was added or changed after this report was attached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Replace Report") { choosingPDF = true }
                Button("Remove Report", role: .destructive) { confirmsRemoval = true }
            } label: {
                Label("Report Options", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(isImporting)
            .confirmationDialog("Remove Lab Report?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove Report", role: .destructive, action: removeReport)
            } message: {
                Text("This removes the copy attached to this container.")
            }
        }
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func loadReport() async {
        isLoading = true
        report = nil
        defer { isLoading = false }
        let containerID = container.labReportContainerID
        do {
            let loaded = try await InventoryLabReportStore.load(for: containerID, legacyID: container.legacyLabReportContainerID)
            if !Task.isCancelled { report = loaded }
        } catch {
            if !Task.isCancelled { errorMessage = String(localized: "Couldn’t load the attached report.") }
        }
    }

    private func importPDF(_ url: URL) {
        let objectID = container.objectID
        let fingerprint = container.labReportStockFingerprint
        isImporting = true
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try InventoryLabReportStore.readPDF(at: url)
                }.value
                try PersistenceController.withJournalStoreWrite {
                    let context = try PersistenceController.shared.journalEditContext()
                    guard let record = try context.existingObject(with: objectID) as? StockContainer,
                          !record.isDeleted, record.labReportStockFingerprint == fingerprint
                    else { throw InventoryLabReportStore.Failure.containerChanged }
                    let identifier = record.labReportID ?? UUID()
                    if record.labReportID == nil {
                        record.labReportID = identifier
                        try PersistenceController.saveJournalChanges(in: context)
                    }
                    let attachment = InventoryLabReport(filename: url.lastPathComponent, stockFingerprint: fingerprint, data: data)
                    try InventoryLabReportStore.local.attach(attachment, to: identifier.uuidString)
                    report = attachment
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeReport() {
        do {
            try InventoryLabReportStore.local.remove(from: container.legacyLabReportContainerID)
            if container.labReportID != nil {
                try InventoryLabReportStore.local.remove(from: container.labReportContainerID)
            }
            report = nil
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn’t remove the attached report.")
        }
    }
}

struct InventoryLabReportLabel: View {
    let filename: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("View Lab Report", systemImage: "doc.text")
            Text(filename)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .privacySensitive()
    }
}

struct InventoryLabReportPreview: View {
    let report: InventoryLabReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InventoryReportPDFView(data: report.data)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    LabeledContent {
                        Text(report.attachedAt, format: .dateTime.day().month().year())
                    } label: {
                        Text("Attached")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.bar)
                }
            .navigationTitle("Lab Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .privacySensitive()
    }
}

private struct InventoryReportPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
