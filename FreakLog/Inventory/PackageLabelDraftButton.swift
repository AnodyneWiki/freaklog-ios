import AVFoundation
import CoreData
import ImageIO
import PhotosUI
import SwiftUI
import Vision
import VisionKit

struct PharmacyPackageCode: Hashable, Identifiable {
    let digits: String
    var id: String { digits }

    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(text.utf8)
        guard bytes.count == 8, bytes.allSatisfy({ (48...57).contains($0) }),
              bytes.contains(where: { $0 != 48 }) else { return nil }
        let sum = bytes.dropLast().enumerated().reduce(0) {
            $0 + ($1.offset + 1) * Int($1.element - 48)
        }
        guard sum % 11 == Int(bytes[7] - 48) else { return nil }
        digits = text
    }

    static func printed(in line: String) -> Self? {
        // Code 39 labels can print the payload underneath the bars.
        if line.hasPrefix("-"), let code = Self(String(line.dropFirst())) { return code }
        guard let match = line.range(of: #"(?i)\bPZN\s*[:\-]?\s*[0-9]{8}\b"#, options: .regularExpression)
        else { return nil }
        return Self(String(line[match].suffix(8)))
    }

    static let symbologies: [VNBarcodeSymbology] = [.code39, .dataMatrix, .ean13]

    static func barcode(_ payload: String, symbology: VNBarcodeSymbology) -> Self? {
        switch symbology {
        case .code39:
            // IFA Code 39 encodes a leading hyphen before the PZN digits.
            guard payload.hasPrefix("-") else { return nil }
            return Self(String(payload.dropFirst()))
        case .dataMatrix:
            // ISO/IEC 15434 Format 06 carries the PPN in its 9N field.
            let fields = payload.split(whereSeparator: { $0 == "\u{1D}" || $0 == "\u{1E}" || $0 == "\u{04}" })
            if let field = fields.first(where: { $0.hasPrefix("9N11") }) {
                return ppn(field.dropFirst(2))
            }
            // GS1 uses application identifier 01 for the 14-digit German NTIN.
            let code = payload.hasPrefix("]d2") ? payload.dropFirst(3) : payload[...]
            if code.hasPrefix("(01)") { return ntin(code.dropFirst(4).prefix(14)) }
            if code.hasPrefix("01") { return ntin(code.dropFirst(2).prefix(14)) }
            return nil
        case .ean13:
            guard payload.count == 13 else { return nil }
            return ntin(Substring("0" + payload))
        default:
            return nil
        }
    }

    private static func ppn(_ payload: Substring) -> Self? {
        let bytes = Array(payload.utf8)
        guard bytes.count == 12, bytes.allSatisfy({ (48...57).contains($0) }),
              payload.hasPrefix("11") else { return nil }
        let sum = bytes.dropLast(2).enumerated().reduce(0) { $0 + ($1.offset + 2) * Int($1.element) }
        guard sum % 97 == Int(bytes[10] - 48) * 10 + Int(bytes[11] - 48) else { return nil }
        return Self(String(payload.dropFirst(2).prefix(8)))
    }

    private static func ntin(_ payload: Substring) -> Self? {
        let bytes = Array(payload.utf8)
        guard bytes.count == 14, bytes.allSatisfy({ (48...57).contains($0) }),
              payload.hasPrefix("04150") else { return nil }
        let sum = bytes.dropLast().reversed().enumerated().reduce(0) {
            $0 + Int($1.element - 48) * ($1.offset.isMultiple(of: 2) ? 3 : 1)
        }
        guard (10 - sum % 10) % 10 == Int(bytes[13] - 48) else { return nil }
        return Self(String(payload.dropFirst(5).prefix(8)))
    }
}

@MainActor
enum PharmacyPackageMatches {
    private static let key = "rememberedPharmacyPackages"

    static func productID(
        for code: PharmacyPackageCode, in context: NSManagedObjectContext, defaults: UserDefaults = .standard
    ) -> NSManagedObjectID? {
        product(for: code, in: context, defaults: defaults)?.object.objectID
    }

    static func product(
        for code: PharmacyPackageCode, in context: NSManagedObjectContext, defaults: UserDefaults = .standard
    ) -> JournalPresetProduct? {
        guard let stored = defaults.dictionary(forKey: key)?[code.digits] as? [String],
              let address = stored.first.flatMap(URL.init(string:)),
              let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: address),
              let product = try? context.existingObject(with: id),
              signature(of: product) == Array(stored.dropFirst()) else { return nil }
        if let unit = product as? CustomUnit { return .customUnit(unit) }
        return (product as? Formulation).map(JournalPresetProduct.formulation)
    }

    static func remember(_ code: PharmacyPackageCode, product: NSManagedObject, defaults: UserDefaults = .standard) {
        guard !product.objectID.isTemporaryID, let signature = signature(of: product) else { return }
        var matches = defaults.dictionary(forKey: key) ?? [:]
        matches[code.digits] = [product.objectID.uriRepresentation().absoluteString] + signature
        defaults.set(matches, forKey: key)
    }

    static func codes(for productID: NSManagedObjectID, defaults: UserDefaults = .standard) -> [PharmacyPackageCode] {
        let address = productID.uriRepresentation().absoluteString
        return (defaults.dictionary(forKey: key) ?? [:]).compactMap { code, match in
            guard (match as? [String])?.first == address else { return nil }
            return PharmacyPackageCode(code)
        }.sorted { $0.digits < $1.digits }
    }

    static func forget(_ code: PharmacyPackageCode, defaults: UserDefaults = .standard) {
        var matches = defaults.dictionary(forKey: key) ?? [:]
        matches.removeValue(forKey: code.digits)
        defaults.set(matches, forKey: key)
    }

    private static func signature(of product: NSManagedObject) -> [String]? {
        guard !product.isDeleted else { return nil }
        if let unit = product as? CustomUnit, !unit.isArchived {
            return [unit.substanceNameUnwrapped, unit.administrationRouteUnwrapped.rawValue, unit.unitUnwrapped,
                    unit.originalUnitUnwrapped, unit.doseUnwrapped.map { String($0) } ?? ""]
        }
        if let formulation = product as? Formulation, !formulation.componentsSorted.isEmpty {
            return formulation.componentsSorted.flatMap {
                [$0.substanceNameUnwrapped, $0.administrationRouteUnwrapped.rawValue, $0.unitsUnwrapped,
                 $0.doseUnwrapped.map { String($0) } ?? ""]
            }
        }
        return nil
    }
}

private enum PackageLabelAction {
    case useLabel((String?, PharmacyPackageCode?) -> Void)
    case logProduct((JournalPresetProduct) -> Void)

    var isLogging: Bool {
        if case .logProduct = self { return true }
        return false
    }
}

struct PackageLabelDraftButton: View {
    private let action: PackageLabelAction

    init(usePackage: @escaping (String?, PharmacyPackageCode?) -> Void) {
        action = .useLabel(usePackage)
    }

    init(logProduct: @escaping (JournalPresetProduct) -> Void) {
        action = .logProduct(logProduct)
    }

    @Environment(\.managedObjectContext) private var context
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var draft: PackageLabelDraft?
    @State private var errorMessage: LocalizedStringKey?
    @State private var scanning = false
    @State private var cameraCode: PharmacyPackageCode?
    @State private var unsupportedBarcode = false
    @State private var reviewedProduct: JournalPresetProduct?

    var body: some View {
        Menu {
            if DataScannerViewController.isSupported {
                Button {
                    Task { await openCamera() }
                } label: {
                    Label("Use Camera", systemImage: "camera")
                }
            }
            Button {
                choosingPhoto = true
            } label: {
                Label("Choose Photo", systemImage: "photo")
            }
            Button { draft = PackageLabelDraft() } label: {
                Label("Enter PZN", systemImage: "number")
            }
        } label: {
            Label("Scan Package", systemImage: "barcode.viewfinder")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .disabled(selectedPhoto != nil)
        .photosPicker(isPresented: $choosingPhoto, selection: $selectedPhoto, matching: .images)
        .task(id: selectedPhoto) { await readSelectedPhoto() }
        .sheet(item: $draft, onDismiss: openReviewedProduct) { draft in
            PackageLabelReview(draft: draft, action: reviewAction)
        }
        .sheet(isPresented: $scanning, onDismiss: {
            if let cameraCode {
                self.cameraCode = nil
                useRecognizedLabel(PackageLabelDraft(codes: [cameraCode]))
            }
        }) {
            NavigationStack {
                VStack(spacing: 0) {
                    LivePackageScanner { code in
                        cameraCode = code
                        scanning = false
                    } onUnsupportedBarcode: {
                        unsupportedBarcode = true
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: String(localized: "No valid PZN in this barcode.")
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if unsupportedBarcode {
                            Label("No Valid PZN in This Barcode", systemImage: "exclamationmark.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Find the barcode near the printed PZN and tap it when highlighted.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                }
                .navigationTitle("Scan Package Barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } }
                }
            }
        }

        if selectedPhoto != nil {
            ProgressView("Reading Label…")
        }
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var reviewAction: PackageLabelAction {
        action.isLogging ? .logProduct { reviewedProduct = $0 } : action
    }

    private func openReviewedProduct() {
        guard let reviewedProduct else { return }
        self.reviewedProduct = nil
        if case .logProduct(let open) = action {
            open(reviewedProduct)
        }
    }

    private func useRecognizedLabel(_ label: PackageLabelDraft) {
        if case .logProduct(let open) = action, label.codes.count == 1,
           let code = label.codes.first, let product = PharmacyPackageMatches.product(for: code, in: context) {
            open(product)
        } else {
            draft = label
        }
    }

    private func openCamera() async {
        errorMessage = nil
        unsupportedBarcode = false
        guard await AVCaptureDevice.requestAccess(for: .video), DataScannerViewController.isAvailable else {
            errorMessage = "Camera scanning is unavailable. Choose a photo or enter the PZN."
            return
        }
        scanning = true
    }

    @MainActor
    private func readSelectedPhoto() async {
        guard let photo = selectedPhoto else { return }
        errorMessage = nil
        defer {
            if !Task.isCancelled, selectedPhoto == photo { selectedPhoto = nil }
        }

        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw PackageLabelRecognition.Error.unreadablePhoto
            }
            try Task.checkCancellation()
            let recognition = Task.detached(priority: .userInitiated) {
                try PackageLabelRecognition.read(in: data)
            }
            let result = try await withTaskCancellationHandler {
                try await recognition.value
            } onCancel: {
                recognition.cancel()
            }
            guard !Task.isCancelled, selectedPhoto == photo else { return }

            if result.codes.isEmpty && (action.isLogging || result.lines.isEmpty) {
                errorMessage = action.isLogging
                    ? "No PZN found. Try a clearer photo of the barcode or enter the PZN."
                    : "No label or PZN found. Try a clearer photo of the package."
            } else {
                useRecognizedLabel(result)
            }
        } catch {
            guard !Task.isCancelled, selectedPhoto == photo else { return }
            errorMessage = "Couldn’t read this photo. Try another photo."
        }
    }
}

private struct PackageLabelDraft: Identifiable {
    let id = UUID()
    var lines: [String] = []
    var codes: [PharmacyPackageCode] = []
}

private struct PackageLabelReview: View {
    let draft: PackageLabelDraft
    let action: PackageLabelAction

    @State private var name = ""
    @State private var pzn: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    init(draft: PackageLabelDraft, action: PackageLabelAction) {
        self.draft = draft
        self.action = action
        _pzn = State(initialValue: draft.codes.count == 1 ? draft.codes[0].digits : "")
    }

    private var code: PharmacyPackageCode? { PharmacyPackageCode(pzn) }

    private var rememberedProduct: JournalPresetProduct? {
        code.flatMap { PharmacyPackageMatches.product(for: $0, in: context) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !action.isLogging {
                        TextField("Product Name (Optional)", text: $name)
                    }
                    TextField("PZN", text: $pzn)
                        .keyboardType(.numberPad)
                    if !pzn.isEmpty, code == nil {
                        Text("Enter the eight-digit PZN printed on the package.")
                            .foregroundStyle(.secondary)
                    }
                    if let rememberedProduct {
                        LabeledContent("Saved Product", value: rememberedProduct.name)
                    } else if action.isLogging, code != nil {
                        Text("This PZN isn’t paired with a saved product. Pair it in Inventory or choose the product manually.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(action.isLogging ? "Check the PZN against the package." : "Check the PZN and product name against the package.")
                }
                if draft.codes.count > 1 {
                    Section("Detected Codes") {
                        ForEach(draft.codes) { code in
                            Button(code.digits) { pzn = code.digits }
                        }
                    }
                }
                if !action.isLogging, !draft.lines.isEmpty {
                    Section("Recognized Text") {
                        ForEach(Array(draft.lines.enumerated()), id: \.offset) { _, line in
                            Button {
                                name = line
                            } label: {
                                Text(verbatim: line)
                            }
                            .accessibilityHint("Use this text as the draft name.")
                        }
                    }
                }
                if !action.isLogging {
                    Section("Medication References") {
                        PackageReferenceLinks(name: name, pzn: code?.digits)
                    }
                }
            }
            .navigationTitle("Review Package Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch action {
                    case .useLabel(let usePackage):
                        Button("Use Label") {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            usePackage(trimmed.isEmpty ? nil : trimmed, code)
                            dismiss()
                        }
                        .disabled(pzn.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : code == nil)
                    case .logProduct(let open):
                        Button("Continue") {
                            guard let rememberedProduct else { return }
                            open(rememberedProduct)
                            dismiss()
                        }
                        .disabled(rememberedProduct == nil)
                    }
                }
            }
        }
    }
}

private struct LivePackageScanner: UIViewControllerRepresentable {
    let onCode: (PharmacyPackageCode) -> Void
    let onUnsupportedBarcode: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onUnsupportedBarcode: onUnsupportedBarcode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: PharmacyPackageCode.symbologies)],
            qualityLevel: .accurate, recognizesMultipleItems: true, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.showError(on: scanner)
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (PharmacyPackageCode) -> Void
        let onUnsupportedBarcode: () -> Void

        init(onCode: @escaping (PharmacyPackageCode) -> Void, onUnsupportedBarcode: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnsupportedBarcode = onUnsupportedBarcode
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                  let code = PharmacyPackageCode.barcode(payload, symbology: barcode.observation.symbology)
            else {
                onUnsupportedBarcode()
                return
            }
            scanner.stopScanning()
            onCode(code)
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            showError(on: scanner)
        }

        func showError(on scanner: DataScannerViewController) {
            Task { @MainActor in
                guard scanner.presentedViewController == nil else { return }
                let alert = UIAlertController(
                    title: String(localized: "Camera Unavailable"),
                    message: String(localized: "Choose a photo or enter the PZN instead."),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                scanner.present(alert, animated: true)
            }
        }
    }
}

private enum PackageLabelRecognition {
    enum Error: Swift.Error {
        case unreadablePhoto
    }

    static func read(in data: Data) throws -> PackageLabelDraft {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw Error.unreadablePhoto }

        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = PharmacyPackageCode.symbologies
        let barcodeRead = Result { try VNImageRequestHandler(cgImage: image).perform([barcodes]) }
        try Task.checkCancellation()
        let textRead = Result { try VNImageRequestHandler(cgImage: image).perform([request]) }
        if case .failure = barcodeRead, case .failure(let error) = textRead {
            throw error
        }

        let lines = (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let barcodeCodes = (barcodes.results ?? []).compactMap { observation -> PharmacyPackageCode? in
            guard let payload = observation.payloadStringValue else { return nil }
            return PharmacyPackageCode.barcode(payload, symbology: observation.symbology)
        }
        let codes = Set(barcodeCodes + lines.compactMap(PharmacyPackageCode.printed)).sorted { $0.digits < $1.digits }
        return PackageLabelDraft(lines: lines, codes: codes)
    }
}
