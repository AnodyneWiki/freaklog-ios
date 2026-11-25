import SwiftUI
import UniformTypeIdentifiers

struct ExperienceReportScreen: View {
    let experience: Experience
    let includesRatings: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var options = ExperienceReport.Options()
    @State private var pendingOptions: ExperienceReport.Options?
    @State private var markdown: String
    @State private var generatedMarkdown: String
    @State private var confirmsRegeneration = false
    @State private var confirmsDiscard = false
    @State private var isExporting = false
    @State private var document: MarkdownDocument?
    @State private var exportError: String?
    @FocusState private var isEditing: Bool

    init(experience: Experience, includesRatings: Bool) {
        self.experience = experience
        self.includesRatings = includesRatings
        let draft = ExperienceReport.markdown(for: experience, includesRatings: includesRatings)
        _markdown = State(initialValue: draft)
        _generatedMarkdown = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let exportError {
                    Section {
                        Label(exportError, systemImage: "exclamationmark.circle")
                    }
                }
                Section {
                    DisclosureGroup("Include in Report") {
                        Toggle("Journal Title", isOn: selection(\.includesTitle))
                        Toggle("Exact Dates and Times", isOn: selection(\.includesDates))
                        Toggle("Location Names", isOn: selection(\.includesLocations))
                        Toggle("Participant Names", isOn: selection(\.includesNames))
                    }
                } footer: {
                    Text("Review the text before sharing. Notes, titles and custom names can contain identifying details.")
                }
                Section("Markdown Preview") {
                    TextEditor(text: $markdown)
                        .font(.body.monospaced())
                        .frame(minHeight: 300)
                        .focused($isEditing)
                        .accessibilityLabel("Report Markdown")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Share Experience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if markdown != generatedMarkdown {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        isEditing = false
                        exportError = nil
                        document = MarkdownDocument(markdown: markdown)
                        isExporting = true
                    }
                    .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Regenerate Report?", isPresented: $confirmsRegeneration, titleVisibility: .visible) {
                Button("Regenerate", role: .destructive) {
                    if let pendingOptions { regenerate(with: pendingOptions) }
                    pendingOptions = nil
                }
                Button("Cancel", role: .cancel) { pendingOptions = nil }
            } message: {
                Text("Changing what’s included replaces your edits to this draft.")
            }
            .confirmationDialog("Discard Report Edits?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard Edits", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: MarkdownDocument.contentType,
                defaultFilename: "Experience Report.md"
            ) { result in
                if case .failure = result {
                    exportError = "The report couldn’t be saved. Your edits are still here."
                }
                document = nil
            }
        }
        .interactiveDismissDisabled(markdown != generatedMarkdown)
    }

    private func selection(_ keyPath: WritableKeyPath<ExperienceReport.Options, Bool>) -> Binding<Bool> {
        Binding {
            options[keyPath: keyPath]
        } set: { value in
            guard options[keyPath: keyPath] != value else { return }
            var updated = options
            updated[keyPath: keyPath] = value
            if markdown == generatedMarkdown {
                regenerate(with: updated)
            } else {
                pendingOptions = updated
                confirmsRegeneration = true
            }
        }
    }

    private func regenerate(with options: ExperienceReport.Options) {
        self.options = options
        let draft = ExperienceReport.markdown(for: experience, options: options, includesRatings: includesRatings)
        generatedMarkdown = draft
        markdown = draft
    }
}

private struct MarkdownDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [contentType] }

    let markdown: String

    init(markdown: String) {
        self.markdown = markdown
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let markdown = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.markdown = markdown
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(markdown.utf8))
    }
}

enum ExperienceReport {
    struct Options: Equatable {
        var includesTitle = false
        var includesDates = false
        var includesLocations = false
        var includesNames = false
    }

    private struct Event {
        let time: Date?
        var endTime: Date?
        let summary: String
    }

    static func markdown(
        for experience: Experience,
        options: Options = Options(),
        includesRatings: Bool
    ) -> String {
        let ingestions = experience.ingestionsSorted
        let names = ingestions.compactMap { Ingestion.storedConsumerName($0.consumerNameUnwrapped) }.uniqued()
        let participants = Dictionary(uniqueKeysWithValues: names.enumerated().map {
            ($0.element, "Participant \($0.offset + 1)")
        })
        let ingestionEvents = ingestions.map { ingestion in
            var details = [inline(ingestion.substanceDisplayName), inline(doseDescription(for: ingestion)),
                           ingestion.administrationRouteUnwrapped.rawValue]
            if let person = Ingestion.storedConsumerName(ingestion.consumerNameUnwrapped) {
                let participant = options.includesNames ? person : (participants[person] ?? "Participant")
                details.append(inline(participant))
            }
            if options.includesLocations, let location = ingestion.location?.name {
                details.append(inline(location))
            }
            if !ingestion.noteUnwrapped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                details.append(inline(ingestion.noteUnwrapped))
            }
            return Event(time: ingestion.time, endTime: ingestion.endTime, summary: details.joined(separator: " · "))
        }
        let notes = experience.timedNotesSorted.map {
            Event(time: $0.time, summary: "Note · \(inline($0.noteUnwrapped))")
        }
        let ratings = includesRatings ? experience.ratingsWithTimeSorted.map {
            Event(time: $0.time, summary: "Rating · \($0.optionUnwrapped.stringRepresentation)")
        } : []
        let events = (ingestionEvents + notes + ratings).sorted {
            ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture)
        }
        let firstIngestion = ingestionEvents.compactMap(\.time).min()
        let anchor = firstIngestion ?? events.compactMap(\.time).first

        let title = options.includesTitle ? inline(experience.titleUnwrapped) : "Experience Report"
        var sections = ["# \(title.isEmpty ? "Experience Report" : title)"]
        var context: [String] = []
        if options.includesDates, let date = anchor ?? experience.sortDate ?? experience.creationDate {
            context.append("Date · \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if options.includesLocations, let location = experience.location?.name {
            context.append("Location · \(inline(location))")
        }
        let text = experience.textUnwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { context.append(text) }
        if includesRatings, let rating = experience.overallRating {
            context.append("Overall rating · \(rating.optionUnwrapped.stringRepresentation)")
        }
        if !context.isEmpty {
            sections.append("## Context\n\n" + context.joined(separator: "\n\n"))
        }

        let substances = ingestions.map(\.substanceDisplayName).uniqued()
        if !substances.isEmpty {
            let summary = substances.map { "- \(inline($0))" }.joined(separator: "\n")
            sections.append("## Ingestion Summary\n\n" + summary)
        }
        if !events.isEmpty {
            var timeline = "## Timeline"
            if anchor != nil {
                timeline += firstIngestion == nil ? "\n\nT+0 is the first timed entry." : "\n\nT+0 is the first recorded ingestion."
            }
            let rows = events.map { event in
                guard let time = event.time, let anchor else {
                    return "- **Time unknown** · \(event.summary)"
                }
                var label = offset(from: anchor, to: time)
                if options.includesDates {
                    label += " (\(time.formatted(date: .abbreviated, time: .shortened)))"
                }
                if let endTime = event.endTime, endTime > time {
                    label += " to \(offset(from: anchor, to: endTime))"
                    if options.includesDates {
                        label += " (\(endTime.formatted(date: .abbreviated, time: .shortened)))"
                    }
                }
                return "- **\(label)** · \(event.summary)"
            }
            sections.append(timeline + "\n\n" + rows.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func doseDescription(for ingestion: Ingestion) -> String {
        if let customDose = ingestion.customUnitDose {
            if let calculated = customDose.calculatedDoseDescription {
                return "\(customDose.doseDescription) (\(calculated))"
            }
            return customDose.doseDescription
        }
        return ingestion.doseUnwrapped?.doseDescription(
            units: ingestion.unitsUnwrapped,
            isEstimate: ingestion.isEstimate,
            standardDeviation: ingestion.estimatedDoseStandardDeviationUnwrapped
        ) ?? "Unknown amount"
    }

    private static func offset(from start: Date, to time: Date) -> String {
        let elapsed = time.timeIntervalSince(start)
        let totalSeconds = Int(abs(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        let sign = elapsed < 0 ? "-" : "+"
        return "T\(sign)" + String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func inline(_ value: String) -> String {
        let singleLine = value.split(whereSeparator: \.isNewline).joined(separator: " ")
        return singleLine.reduce(into: "") { result, character in
            if "\\`*_[]<>".contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}
