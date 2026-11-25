import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct SelectiveExportScreen: View {
    enum Kind {
        case journal
        case clinician

        var title: String {
            switch self {
            case .journal: "Journal Summary"
            case .clinician: "Clinician Summary"
            }
        }
    }

    private enum Person: Hashable {
        case everyone
        case me
        case named(String)

        func matches(_ ingestion: Ingestion) -> Bool {
            switch self {
            case .everyone: true
            case .me: ingestion.isMine
            case .named(let name): ingestion.consumerNameUnwrapped == name
            }
        }
    }

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    private var allIngestions: FetchedResults<Ingestion>
    @FetchRequest(fetchRequest: PersistenceController.experiencesRequest())
    private var allExperiences: FetchedResults<Experience>

    private let kind: Kind
    private let sourceIngestions: [Ingestion]?
    private let sourceExperiences: [Experience]?
    private let sourceRange: DateInterval?

    @State private var usesDateRange: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var substance: String?
    @State private var tag: String?
    @State private var route: AdministrationRoute?
    @State private var person: Person
    @State private var options: SelectiveJournalReport.Options
    @State private var draft: SelectiveJournalReport?

    init(
        kind: Kind = .journal, ingestions: [Ingestion]? = nil, experiences: [Experience]? = nil,
        dateRange: DateInterval? = nil
    ) {
        self.kind = kind
        sourceIngestions = ingestions
        sourceExperiences = experiences
        sourceRange = dateRange
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let recent = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        _usesDateRange = State(initialValue: kind == .clinician)
        _startDate = State(initialValue: dateRange?.start ?? recent)
        _endDate = State(initialValue: dateRange.map { max($0.start, $0.end.addingTimeInterval(-1)) } ?? today)
        _person = State(initialValue: kind == .clinician ? .me : .everyone)
        _options = State(initialValue: .init(exactDates: kind == .clinician))
    }

    var body: some View {
        let selection = selection
        Form {
            Section("Period") {
                Toggle("Limit by Date", isOn: $usesDateRange)
                if usesDateRange {
                    DatePicker("From", selection: $startDate, in: ...max(startDate, endDate), displayedComponents: .date)
                    DatePicker("Through", selection: $endDate, in: min(startDate, endDate)..., displayedComponents: .date)
                }
                if let sourceRange {
                    LabeledContent("Stats Period") {
                        Text(displayRange(sourceRange)).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Filters") {
                Picker("Substance", selection: $substance) {
                    Text("All Substances").tag(nil as String?)
                    ForEach(substances, id: \.self) { name in
                        Text(PersistenceController.shared.displayName(for: name)).tag(Optional(name))
                    }
                }
                if !tags.isEmpty {
                    Picker("Tag", selection: $tag) {
                        Text("All Tags").tag(nil as String?)
                        ForEach(tags, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                }
                Picker("Route", selection: $route) {
                    Text("All Routes").tag(nil as AdministrationRoute?)
                    ForEach(routes, id: \.self) { route in
                        Text(route.rawValue.capitalized).tag(Optional(route))
                    }
                }
                Picker("Person", selection: $person) {
                    Text("Everyone").tag(Person.everyone)
                    Text("Me").tag(Person.me)
                    ForEach(people, id: \.self) { name in
                        Text(name).tag(Person.named(name))
                    }
                }
            }

            Section {
                Toggle("Exact Dates and Times", isOn: $options.exactDates)
                Toggle("Notes and Titles", isOn: $options.notes)
                Toggle("Ratings", isOn: $options.ratings)
                Toggle("Location Names", isOn: $options.locations)
                Toggle("Participant Names", isOn: $options.names)
                Toggle("Administration Sites", isOn: $options.sites)
            } header: {
                Text("Include")
            } footer: {
                Text("Review the report before sharing. Custom names and notes can contain identifying details.")
            }

            Section("Selection") {
                LabeledContent("Experiences", value: selection.experiences.count.formatted())
                LabeledContent("Ingestions", value: selection.ingestions.count.formatted())
                Button("Review Export") {
                    draft = SelectiveJournalReport(
                        kind: kind, ingestions: selection.ingestions, experiences: selection.experiences,
                        range: selectedRange, options: options)
                }
                .disabled(selection.experiences.isEmpty && selection.ingestions.isEmpty)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { report in
            SelectiveExportReview(report: report)
        }
    }

    private var ingestions: [Ingestion] { sourceIngestions ?? Array(allIngestions) }

    private var participants: [String] {
        ingestions.compactMap { Ingestion.storedConsumerName($0.consumerNameUnwrapped) }
    }

    private var substances: [String] {
        Set(ingestions.map(\.substanceNameUnwrapped)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var routes: [AdministrationRoute] {
        let recorded = Set(ingestions.compactMap(ReportMarkdown.recordedRoute))
        return AdministrationRoute.allCases.filter(recorded.contains)
    }

    private var tags: [String] {
        PersonalSubstanceTags(substances.flatMap { PersistenceController.shared.personalTags(for: $0).names }).names
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var people: [String] {
        Set(participants).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedRange: DateInterval? {
        guard usesDateRange else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: lastDay), start <= end else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private var selection: (ingestions: [Ingestion], experiences: Set<Experience>) {
        let range = selectedRange
        let all = ingestions
        let taggedNames = tag.map { tag in
            Set(substances.filter { PersistenceController.shared.personalTags(for: $0).contains(tag) })
        }
        let selected = all.filter {
            (substance == nil || $0.substanceNameUnwrapped == substance)
                && (taggedNames?.contains($0.substanceNameUnwrapped) ?? true)
                && (route == nil || ReportMarkdown.recordedRoute($0) == route)
                && person.matches($0)
                && SelectiveJournalReport.includes($0.time, in: range)
        }
        let selectedExperiences = Set(selected.compactMap(\.experience))
        guard substance == nil, tag == nil, route == nil, person == .everyone else {
            return (selected, selectedExperiences)
        }
        if range == nil, let sourceExperiences {
            return (selected, selectedExperiences.union(sourceExperiences))
        }
        // Experiences excluded by an ingestion filter shouldn't reappear as contextual notes.
        let experiencesWithIngestions = Set(all.compactMap(\.experience))
        let otherExperiences = (sourceExperiences ?? Array(allExperiences)).filter {
            !experiencesWithIngestions.contains($0)
                && SelectiveJournalReport.includes($0.sortDate ?? $0.creationDate, in: range)
        }
        return (selected, selectedExperiences.union(otherExperiences))
    }

    private func displayRange(_ range: DateInterval) -> String {
        SelectiveJournalReport.periodLabel(range)
    }
}

struct SelectiveJournalReport: Identifiable {
    struct Options {
        var exactDates = false
        var notes = false
        var ratings = false
        var locations = false
        var names = false
        var sites = false
    }

    let id = UUID()
    let title: String
    let markdown: String
    let included: [String]
    let excluded: [String]

    init(
        kind: SelectiveExportScreen.Kind, ingestions: [Ingestion], experiences: Set<Experience>, range: DateInterval?,
        options: Options
    ) {
        title = kind.title
        let ingestions = ingestions.sorted {
            ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture)
        }
        let experiences = experiences.sorted {
            ($0.sortDate ?? $0.creationDate ?? .distantFuture) < ($1.sortDate ?? $1.creationDate ?? .distantFuture)
        }
        let datedEntries = ingestions.compactMap(\.time)
            + experiences.compactMap { $0.sortDate ?? $0.creationDate }
        let referenceDate = range?.start ?? datedEntries.min()
        let limits: [(String, Bool)] = [
            ("Exact dates and times", options.exactDates),
            ("Notes and titles", options.notes),
            ("Ratings", options.ratings),
            ("Location names", options.locations),
            ("Participant names", options.names),
            ("Administration sites", options.sites),
        ]
        included = ["Selected journal records", "Substances, routes and recorded amounts"]
            + limits.filter { $0.1 }.map { $0.0 }
        excluded = ["App settings, integrations, inventory and coordinates"] + limits.filter { !$0.1 }.map { $0.0 }

        var sections = ["# \(title)", "Self-reported journal entries from FreakLog."]
        if options.exactDates, let range, range.start < range.end {
            sections.append("Reporting period \(Self.periodLabel(range)).")
        }
        let experienceCount = experiences.count == 1 ? "1 experience" : "\(experiences.count.formatted()) experiences"
        let ingestionCount = ingestions.count == 1 ? "1 ingestion" : "\(ingestions.count.formatted()) ingestions"
        sections.append("\(experienceCount.capitalized) and \(ingestionCount).")
        if !ingestions.isEmpty {
            func row(for ingestion: Ingestion, includesSubstance: Bool) -> String {
                let start = Self.timeLabel(ingestion.time, relativeTo: referenceDate, exact: options.exactDates)
                let time: String
                if options.exactDates, let endTime = ingestion.endTime, let startTime = ingestion.time, endTime > startTime {
                    time = start + " to " + Self.timeLabel(endTime, relativeTo: referenceDate, exact: true)
                } else {
                    time = start
                }
                let amount = ReportMarkdown.recordedAmount(ingestion)
                let details = includesSubstance
                    ? ReportMarkdown.ingestion(ingestion, amount: amount)
                    : ReportMarkdown.amountAndRoute(ingestion, amount: amount)
                var row = "- \(time) - " + details
                if options.sites, let site = ingestion.administrationSite, !site.isEmpty {
                    row += ". Site recorded as \(ReportMarkdown.inline(site))"
                }
                if !ingestion.isMine {
                    let name = options.names ? Ingestion.storedConsumerName(ingestion.consumerNameUnwrapped) : nil
                    row += ". Recorded for \(ReportMarkdown.inline(name ?? "another participant"))"
                }
                if options.locations, let location = ingestion.location?.name, !location.isEmpty {
                    row += ". Location recorded as \(ReportMarkdown.inline(location))"
                }
                if options.notes {
                    let note = ReportMarkdown.inline(ingestion.noteUnwrapped)
                    if !note.isEmpty { row += ". " + note }
                }
                return row
            }
            if kind == .clinician {
                let groups = Dictionary(grouping: ingestions, by: \.substanceNameUnwrapped)
                let names = groups.keys.sorted {
                    (groups[$0]?.first?.substanceDisplayName ?? $0).localizedStandardCompare(
                        groups[$1]?.first?.substanceDisplayName ?? $1
                    ) == .orderedAscending
                }
                let history = names.map { name in
                    let entries = groups[name, default: []]
                    let title = ReportMarkdown.inline(entries.first?.substanceDisplayName ?? name)
                    return "### \(title)\n\n" + entries.map { row(for: $0, includesSubstance: false) }.joined(separator: "\n")
                }
                sections.append("## Recorded Use\n\n" + history.joined(separator: "\n\n"))
            } else {
                sections.append("## Ingestions\n\n" + ingestions.map { row(for: $0, includesSubstance: true) }.joined(separator: "\n"))
            }
        }
        if options.notes || options.ratings || options.locations {
            let ingestionsByExperience = Dictionary(grouping: ingestions, by: \.experience)
            let sectionsForExperiences = experiences.compactMap { experience -> String? in
                var rows: [String] = []
                if options.notes {
                    let text = ReportMarkdown.paragraphs(experience.textUnwrapped)
                    if !text.isEmpty { rows.append(text) }
                    rows += experience.timedNotesSorted.filter { Self.includes($0.time, in: range) }.compactMap { note in
                        let text = ReportMarkdown.inline(note.noteUnwrapped)
                        guard !text.isEmpty else { return nil }
                        let time = Self.timeLabel(note.time, relativeTo: referenceDate, exact: options.exactDates)
                        return "- \(time) - \(text)"
                    }
                }
                if options.ratings {
                    rows += experience.ratingsUnwrapped.filter { Self.includes($0.time, in: range) || $0.time == nil }.map {
                        "- Rated \($0.optionUnwrapped.stringRepresentation)."
                    }
                }
                if options.locations, let name = experience.location?.name, !name.isEmpty {
                    rows.append("Location recorded as \(ReportMarkdown.inline(name)).")
                }
                let title = options.notes ? ReportMarkdown.inline(experience.titleUnwrapped) : ""
                guard !rows.isEmpty || !title.isEmpty else { return nil }
                let time = ingestionsByExperience[experience]?.first?.time ?? experience.sortDate ?? experience.creationDate
                let date = Self.timeLabel(time, relativeTo: referenceDate, exact: options.exactDates)
                let heading = title.isEmpty ? "### \(date)" : "### \(title)\n\n\(date)"
                return ([heading] + rows).joined(separator: "\n\n")
            }
            if !sectionsForExperiences.isEmpty {
                sections.append("## Experience Details\n\n" + sectionsForExperiences.joined(separator: "\n\n"))
            }
        }
        markdown = sections.joined(separator: "\n\n") + "\n"
    }

    static func includes(_ date: Date?, in range: DateInterval?) -> Bool {
        guard let range else { return true }
        guard let date else { return false }
        return date >= range.start && date < range.end
    }

    static func periodLabel(_ range: DateInterval) -> String {
        let lastDate = max(range.start, range.end.addingTimeInterval(-1))
        if Calendar.current.isDate(range.start, inSameDayAs: lastDate) {
            return range.start.formatted(date: .abbreviated, time: .omitted)
        }
        return (range.start..<lastDate).formatted(.interval.year().month(.abbreviated).day())
    }

    private static func timeLabel(_ date: Date?, relativeTo reference: Date?, exact: Bool) -> String {
        guard let date else { return "Time unknown" }
        if exact { return date.formatted(date: .abbreviated, time: .shortened) }
        guard let reference else { return "Date omitted" }
        let calendar = Calendar.current
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day ?? 0
        if offset < 0 { return "Before selected period" }
        return "Day \((offset + 1).formatted())"
    }
}

private struct SelectiveExportReview: View {
    let report: SelectiveJournalReport
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.circle")
                }
                Section("Preview") {
                    MarkdownReportPreview(markdown: report.markdown)
                }
                Section("What This File Contains") {
                    DisclosureGroup("Included") {
                        ForEach(report.included, id: \.self) { Text($0) }
                    }
                    DisclosureGroup("Excluded") {
                        ForEach(report.excluded, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Review Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        exportError = nil
                        isExporting = true
                    }
                }
            }
            .fileExporter(
                isPresented: $isExporting, document: MarkdownDocument(markdown: report.markdown),
                contentType: MarkdownDocument.contentType, defaultFilename: report.title + ".md"
            ) { result in
                if case .failure = result { exportError = "The summary couldn’t be saved." }
            }
        }
    }
}
