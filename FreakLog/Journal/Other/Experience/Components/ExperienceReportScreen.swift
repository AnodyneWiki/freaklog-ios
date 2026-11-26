import CoreText
import CoreTransferable
import SwiftUI
import UIKit
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
    @State private var exportError: String?
    @State private var timelineImage: TimelineImageReview.Content?
    @State private var reviewsTimelineImage = false
    @State private var showsEditor = false

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
                        Toggle("Notes", isOn: selection(\.includesNotes))
                    }
                } footer: {
                    Text("Review the text before sharing. Notes, titles and custom names can contain identifying details.")
                }
                Section("Preview") {
                    Button {
                        showsEditor = true
                    } label: {
                        Label("Edit Draft", systemImage: "square.and.pencil")
                    }
                    MarkdownReportPreview(markdown: markdown)
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
                    Menu {
                        ShareLink(item: SharedMarkdown(markdown: markdown),
                                  preview: SharePreview("Experience Report")) {
                            Label("Markdown", systemImage: "doc.text")
                        }
                        Button {
                            exportError = nil
                            do {
                                timelineImage = TimelineImageReview.Content(
                                    file: try ReportRendering.timelineImage(markdown),
                                    markdown: markdown
                                )
                                reviewsTimelineImage = true
                            } catch {
                                exportError = error.localizedDescription
                            }
                        } label: {
                            Label("Timeline Image", systemImage: "photo")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
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
            .navigationDestination(isPresented: $showsEditor) {
                ReportDraftEditor(markdown: $markdown)
            }
            .navigationDestination(isPresented: $reviewsTimelineImage) {
                if let timelineImage {
                    TimelineImageReview(content: timelineImage)
                }
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

private struct ReportDraftEditor: View {
    @Binding var markdown: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TextEditor(text: $markdown)
            .font(.body)
            .padding(.horizontal)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityLabel("Report Draft")
            .navigationTitle("Edit Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

private struct TimelineImageReview: View {
    struct Content {
        let file: SharedTimelineImage
        let markdown: String
    }

    let content: Content
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var showsReportText = false

    var body: some View {
        Group {
            if let image = UIImage(data: content.file.data) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: max(1, geometry.size.width - 24) * clampedZoom(zoom * magnification))
                            .accessibilityLabel("Timeline Image")
                            .padding(12)
                    }
                    .simultaneousGesture(MagnificationGesture()
                        .updating($magnification) { value, state, _ in state = value }
                        .onEnded { zoom = clampedZoom(zoom * $0) })
                }
            } else {
                Label("The timeline image couldn’t be opened.", systemImage: "exclamationmark.circle")
                    .padding()
            }
        }
        .navigationTitle("Review Timeline Image")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showsReportText = true
                    } label: {
                        Label("Read Report Text", systemImage: "doc.text")
                    }
                    Section("Zoom") {
                        Button("Fit Width") { zoom = 1 }
                        Button("150%") { zoom = 1.5 }
                        Button("200%") { zoom = 2 }
                    }
                } label: {
                    Label("Preview Options", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                ShareLink(item: content.file, preview: SharePreview("Experience Timeline"))
            }
        }
        .navigationDestination(isPresented: $showsReportText) {
            ScrollView {
                MarkdownReportPreview(markdown: content.markdown)
                    .padding(.horizontal)
            }
            .navigationTitle("Report Text")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func clampedZoom(_ proposed: CGFloat) -> CGFloat {
        min(3, max(1, proposed))
    }
}

struct SharedMarkdown: Transferable {
    static let contentType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText

    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: contentType) { report in
            Data(report.markdown.utf8)
        }
        .suggestedFileName("FreakLog Report")
    }
}

struct SharedClinicianPDF: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName("Clinician Summary")
    }
}

struct SharedTimelineImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("Experience Timeline")
    }
}

/// PDF and PNG rendering only accepts the reviewed copy, so no journal data can
/// bypass the report's selection, redaction or draft edits.
@MainActor
enum ReportRendering {
    enum RenderingError: LocalizedError {
        case imageTooLong
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .imageTooLong:
                "This report is too long for one image. Share the Markdown report or shorten the draft."
            case .unreadableImage:
                "The timeline image couldn’t be generated. Your draft is still here."
            }
        }
    }

    static func clinicianPDF(_ markdown: String) -> SharedClinicianPDF {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let content = page.insetBy(dx: 46, dy: 48)
        let text = styled(markdown, timeline: false)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Clinician Summary"]
        let data = UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            var offset = 0
            repeat {
                context.beginPage()
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0),
                                                    CGPath(rect: content, transform: nil), nil)
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: page.height)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()
                let drawn = CTFrameGetVisibleStringRange(frame).length
                guard drawn > 0 else { break }
                offset += drawn
            } while offset < text.length
        }
        return SharedClinicianPDF(data: data)
    }

    static func timelineImage(_ markdown: String) throws -> SharedTimelineImage {
        guard markdown.utf16.count <= 24_000 else { throw RenderingError.imageTooLong }
        let margin: CGFloat = 28
        let contentWidth: CGFloat = 442
        let text = styled(markdown, timeline: true)
        let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let height = ceil(text.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                            options: drawOptions, context: nil).height)
        let size = CGSize(width: contentWidth + 2 * margin, height: height + 2 * margin)
        guard height.isFinite, size.height <= 4_000 else { throw RenderingError.imageTooLong }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            text.draw(with: CGRect(x: margin, y: margin, width: contentWidth, height: height),
                      options: drawOptions, context: nil)
        }
        guard !png.isEmpty else { throw RenderingError.unreadableImage }
        return SharedTimelineImage(data: png)
    }

    private static func styled(_ markdown: String, timeline: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let prefix = ["### ", "## ", "# "].first(where: line.hasPrefix)
            let isBullet = line.hasPrefix("- ")
            let content = line.dropFirst(prefix?.count ?? (isBullet ? 2 : 0))
            let visible = (try? AttributedString(markdown: String(content), options: .init(interpretedSyntax: .inlineOnly)))
                .map { String($0.characters) } ?? String(content)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = line.isEmpty ? 1 : 4
            paragraph.lineSpacing = timeline ? 2 : 1
            if isBullet {
                paragraph.headIndent = 15
            }
            let font: UIFont
            switch prefix {
            case "# ": font = .boldSystemFont(ofSize: timeline ? 26 : 23)
            case "## ": font = .boldSystemFont(ofSize: timeline ? 18 : 15)
            case "### ": font = .boldSystemFont(ofSize: timeline ? 16 : 13)
            default: font = .systemFont(ofSize: line.isEmpty ? 6 : (timeline ? 14 : 11))
            }
            let bullet = isBullet ? "•  " : ""
            let row = NSMutableAttributedString(string: bullet + visible + "\n", attributes: [
                .font: font, .foregroundColor: UIColor(white: 0.1, alpha: 1),
                .paragraphStyle: paragraph,
            ])
            if timeline, visible.hasPrefix("T"), let split = visible.range(of: " - ") {
                let marker = bullet + visible[..<split.lowerBound]
                row.addAttributes([.foregroundColor: UIColor(red: 0.05, green: 0.3, blue: 0.58, alpha: 1),
                                   .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)],
                                  range: NSRange(location: 0, length: marker.utf16.count))
            }
            result.append(row)
        }
        return result
    }
}

enum ExperienceReport {
    struct Options: Equatable {
        var includesTitle = false
        var includesDates = false
        var includesLocations = false
        var includesNames = false
        var includesNotes = true
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
            if options.includesNotes {
                let note = ReportMarkdown.inline(ingestion.noteUnwrapped)
                if !note.isEmpty { summary += ". " + note }
            }
            return Event(time: ingestion.time, endTime: ingestion.endTime, summary: summary)
        }
        let notes = (options.includesNotes ? experience.timedNotesSorted : []).compactMap { note -> Event? in
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
        let narrative = options.includesNotes ? ReportMarkdown.paragraphs(experience.textUnwrapped) : ""
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
