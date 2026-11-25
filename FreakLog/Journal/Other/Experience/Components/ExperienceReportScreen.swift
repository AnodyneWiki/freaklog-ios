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
    @State private var showsEditor = false
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
                Section {
                    if showsEditor {
                        TextEditor(text: $markdown)
                            .font(.body)
                            .frame(minHeight: 300)
                            .focused($isEditing)
                            .accessibilityLabel("Report Draft")
                    } else {
                        MarkdownReportPreview(markdown: markdown)
                    }
                } header: {
                    HStack {
                        Text(showsEditor ? "Draft" : "Preview")
                        Spacer()
                        Button(showsEditor ? "Done Editing" : "Edit Draft") {
                            showsEditor.toggle()
                            isEditing = showsEditor
                        }
                        .textCase(nil)
                        .buttonStyle(.borderless)
                    }
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
                    Button("Save") {
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

struct MarkdownDocument: FileDocument {
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
            var summary = ReportMarkdown.ingestion(ingestion, amount: doseDescription(for: ingestion))
            if let person = Ingestion.storedConsumerName(ingestion.consumerNameUnwrapped) {
                let participant = options.includesNames ? person : (participants[person] ?? "Participant")
                summary += " for \(ReportMarkdown.inline(participant))"
            }
            if options.includesLocations, let location = ingestion.location?.name, !location.isEmpty {
                summary += " at \(ReportMarkdown.inline(location))"
            }
            let note = ReportMarkdown.inline(ingestion.noteUnwrapped)
            if !note.isEmpty { summary += ". " + note }
            return Event(time: ingestion.time, endTime: ingestion.endTime, summary: summary)
        }
        let notes = experience.timedNotesSorted.compactMap { note -> Event? in
            let text = ReportMarkdown.inline(note.noteUnwrapped)
            return text.isEmpty ? nil : Event(time: note.time, summary: text)
        }
        let ratings = includesRatings ? experience.ratingsWithTimeSorted.map {
            Event(time: $0.time, summary: "Rated \($0.optionUnwrapped.stringRepresentation).")
        } : []
        let observations = (notes + ratings).sorted {
            ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture)
        }
        let firstIngestion = ingestionEvents.compactMap(\.time).min()
        let anchor = firstIngestion ?? observations.compactMap(\.time).first

        let title = options.includesTitle ? ReportMarkdown.inline(experience.titleUnwrapped) : ""
        var sections = ["# \(title.isEmpty ? "Experience Report" : title)"]
        if options.includesDates, let date = anchor ?? experience.sortDate ?? experience.creationDate {
            sections.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if options.includesLocations, let location = experience.location?.name, !location.isEmpty {
            sections.append("Setting recorded as \(ReportMarkdown.inline(location)).")
        }

        func rows(_ events: [Event]) -> String {
            events.map { event in
                guard let time = event.time, let anchor else { return "- \(event.summary)" }
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
                return "- \(label) - \(event.summary)"
            }.joined(separator: "\n")
        }

        if !ingestionEvents.isEmpty {
            var dosing = "## Recorded Doses"
            if firstIngestion != nil { dosing += "\n\nT+0 marks the first recorded ingestion." }
            sections.append(dosing + "\n\n" + rows(ingestionEvents))
        }
        let narrative = ReportMarkdown.paragraphs(experience.textUnwrapped)
        if !narrative.isEmpty { sections.append(narrative) }
        if !observations.isEmpty {
            var timeline = "## Timed Notes"
            if firstIngestion == nil && anchor != nil { timeline += "\n\nT+0 marks the first timed entry." }
            sections.append(timeline + "\n\n" + rows(observations))
        }
        if includesRatings, let rating = experience.overallRating {
            sections.append("Overall rating \(rating.optionUnwrapped.stringRepresentation).")
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func doseDescription(for ingestion: Ingestion) -> String {
        if let customDose = ingestion.customUnitDose {
            if let calculated = customDose.calculatedDoseDescription {
                return "\(ReportMarkdown.estimateWords(customDose.doseDescription)) (\(ReportMarkdown.estimateWords(calculated)))"
            }
            return ReportMarkdown.estimateWords(customDose.doseDescription)
        }
        return ReportMarkdown.recordedAmount(ingestion)
    }

    private static func offset(from start: Date, to time: Date) -> String {
        let elapsed = time.timeIntervalSince(start)
        guard abs(elapsed) < Double(Int.max) else { return "Time unknown" }
        let totalSeconds = Int(abs(elapsed))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        let sign = elapsed < 0 ? "-" : "+"
        if totalSeconds == 0 { return "T+0" }
        let parts = [(hours, "h"), (minutes, "m"), (seconds, "s")].compactMap { value, unit in
            value > 0 ? "\(value)\(unit)" : nil
        }
        return "T\(sign)" + parts.joined(separator: " ")
    }
}

enum ReportMarkdown {
    static func inline(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .reduce(into: "") { result, character in
                if "\\`*_[]<#".contains(character) { result.append("\\") }
                result.append(character)
            }
    }

    static func paragraphs(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").map(inline).filter { !$0.isEmpty }
            .map { text in
                // Keep leading list markers from turning journal notes into report structure.
                text.range(of: #"^([-+]|[0-9]+[.)]) "#, options: .regularExpression) != nil
                    ? text.replacingOccurrences(of: #"^([0-9]*)([-+.)])"#, with: "$1\\$2", options: .regularExpression)
                    : text
            }
            .joined(separator: "\n\n")
    }

    static func ingestion(_ ingestion: Ingestion, amount: String) -> String {
        "\(inline(ingestion.substanceDisplayName)) (\(amountAndRoute(ingestion, amount: amount)))"
    }

    static func amountAndRoute(_ ingestion: Ingestion, amount: String) -> String {
        let route = recordedRoute(ingestion)?.rawValue ?? "route not recorded"
        return "\(inline(amount)), \(route)"
    }

    static func recordedRoute(_ ingestion: Ingestion) -> AdministrationRoute? {
        ingestion.administrationRoute.flatMap { AdministrationRoute(rawValue: $0.lowercased()) }
    }

    static func recordedAmount(_ ingestion: Ingestion) -> String {
        guard let dose = ingestion.doseUnwrapped, dose.isFinite else { return "Unknown amount" }
        let units = ingestion.unitsUnwrapped
        let amount = dose.formatted(.number.precision(.significantDigits(1...17)))
        let quantity = units.isEmpty ? amount : "\(amount) \(units)"
        guard ingestion.isEstimate else { return quantity }
        if let deviation = ingestion.estimatedDoseStandardDeviationUnwrapped, deviation.isFinite, deviation > 0 {
            let formattedDeviation = deviation.formatted(.number.precision(.significantDigits(1...17)))
            return "\(quantity) (plus or minus \(formattedDeviation))"
        }
        return "about " + quantity
    }

    static func estimateWords(_ description: String) -> String {
        if description.hasPrefix("~") { return "about " + description.dropFirst() }
        return description.replacingOccurrences(of: "±", with: " plus or minus ")
    }
}

struct MarkdownReportPreview: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = markdown.components(separatedBy: .newlines)
            ForEach(lines.indices, id: \.self) { index in
                let line = lines[index]
                if line.hasPrefix("# ") {
                    formatted(line.dropFirst(2), font: .title2.bold(), isHeading: true)
                } else if line.hasPrefix("## ") || line.hasPrefix("### ") {
                    let prefix = line.hasPrefix("### ") ? 4 : 3
                    formatted(line.dropFirst(prefix), font: .headline, isHeading: true)
                } else if line.hasPrefix("- ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        formatted(line.dropFirst(2))
                    }
                    .padding(.bottom, 5)
                } else if !line.isEmpty {
                    formatted(line[...])
                } else if index < lines.count - 1 {
                    Spacer(minLength: 10).frame(height: 10).accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .textSelection(.enabled)
    }

    private func formatted(_ line: Substring, font: Font = .body, isHeading: Bool = false) -> some View {
        let text = (try? AttributedString(markdown: String(line), options: .init(interpretedSyntax: .inlineOnly)))
            ?? AttributedString(String(line))
        return Text(text).font(font).accessibilityAddTraits(isHeading ? .isHeader : [])
    }
}
