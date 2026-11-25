import ImageIO
import PhotosUI
import SwiftUI
import Vision

struct PackageLabelDraftButton: View {
    let useName: (String) -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var draft: PackageLabelDraft?
    @State private var errorMessage: LocalizedStringKey?

    var body: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Read Package Label", systemImage: "text.viewfinder")
        }
        .accessibilityHint("Choose a photo of the package.")
        .disabled(selectedPhoto != nil)
        .task(id: selectedPhoto) { await readSelectedPhoto() }
        .sheet(item: $draft) { draft in
            PackageLabelReview(draft: draft, useName: useName)
        }

        if selectedPhoto != nil {
            ProgressView("Reading Label…")
        }
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
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
                try PackageLabelRecognition.readLines(in: data)
            }
            let lines = try await withTaskCancellationHandler {
                try await recognition.value
            } onCancel: {
                recognition.cancel()
            }
            guard !Task.isCancelled, selectedPhoto == photo else { return }

            if lines.isEmpty {
                errorMessage = "No readable text found. Try a clearer photo of the label."
            } else {
                draft = PackageLabelDraft(lines: lines)
            }
        } catch {
            guard !Task.isCancelled, selectedPhoto == photo else { return }
            errorMessage = "Couldn’t read this photo. Try another photo."
        }
    }
}

private struct PackageLabelDraft: Identifiable {
    let id = UUID()
    let lines: [String]
}

private struct PackageLabelReview: View {
    let draft: PackageLabelDraft
    let useName: (String) -> Void

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product Name", text: $name)
                } footer: {
                    Text("Choose a line below or enter the name as printed on the package.")
                }
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
            .navigationTitle("Review Package Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Name") {
                        useName(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private enum PackageLabelRecognition {
    enum Error: Swift.Error {
        case unreadablePhoto
    }

    static func readLines(in data: Data) throws -> [String] {
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
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        return (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
