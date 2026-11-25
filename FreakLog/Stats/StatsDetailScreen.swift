import Charts
import SwiftUI

struct StatsDetailScreen: View {
    let metric: StatsMetric
    @State private var selection: StatsSelection
    @State private var selectedBucket: Date?
    @State private var isShowingFilters = false
    @State private var groupsByPrimaryTag = false
    @State private var substanceOrder = StatsSubstanceOrder.count
    @State private var shareSelection: StatsRecords?
    @State private var isNamingView = false
    @State private var pinName = ""
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(StatsPreferences.pinnedViewsKey) private var pinnedStatsData = Data()

    init(metric: StatsMetric, selection: StatsSelection) {
        self.metric = metric
        _selection = State(initialValue: selection)
    }

    var body: some View {
        StatsJournal { entries, tags in
            let records = StatsRecords(entries: entries, selection: effectiveSelection, tags: tags)
            let buckets = records.buckets(for: metric)
            let bucket = buckets.first { $0.id == selectedBucket }
            let focused = bucket.map { records.selecting($0, for: metric) } ?? records
            List {
                periodSection

                if metric != .gaps {
                    chartSection(records: records, buckets: buckets, focused: focused, selected: bucket)
                    breakdown(focused, tags: tags)
                    if metric == .ingestions, effectiveSelection.substance != nil, !focused.entries.isEmpty {
                        amountsSection(focused)
                        if effectiveSelection.person != .everyone, records.entries.count > 1 {
                            Section {
                                NavigationLink {
                                    StatsDetailScreen(metric: .gaps, selection: effectiveSelection)
                                } label: {
                                    Label("Time Between Logs", systemImage: "clock")
                                }
                            }
                        }
                    }
                } else if effectiveSelection.substance != nil && effectiveSelection.person != .everyone {
                    gapSection(focused.gapsBetweenLogs)
                } else {
                    Section {
                        Text("Choose one substance and one person to see the time between their logs.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(detailTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Label("Filters", systemImage: selection.hasFilters
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    Menu {
                        Button {
                            shareSelection = focused
                        } label: {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                        .disabled(focused.entries.isEmpty)
                        Button {
                            pinName = ""
                            isNamingView = true
                        } label: {
                            Label("Pin View", systemImage: "pin")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: buckets.map(\.id)) { updatedBuckets in
                if let selectedBucket, !updatedBuckets.contains(selectedBucket) {
                    self.selectedBucket = nil
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                StatsFiltersScreen(selection: $selection, entries: entries, tagNames: Set(tags.values.flatMap(\.names)))
            }
        }
        .sheet(isPresented: Binding(
            get: { shareSelection != nil },
            set: { if !$0 { shareSelection = nil } }
        )) {
            if let shareSelection {
                NavigationStack {
                    SelectiveExportScreen(
                        ingestions: shareSelection.entries,
                        experiences: shareSelection.experiences.map(\.experience),
                        dateRange: shareSelection.range.start == .distantPast ? nil : shareSelection.range
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { self.shareSelection = nil }
                        }
                    }
                }
            }
        }
        .onAppear { clearHiddenRoute() }
        .onChange(of: selection) { _ in selectedBucket = nil }
        .onChange(of: isEyeOpen) { _ in clearHiddenRoute() }
        .alert("Pin Stats View", isPresented: $isNamingView) {
            TextField("Name", text: $pinName)
            Button("Cancel", role: .cancel) {}
            Button("Pin") { pinView() }
                .disabled(pinName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The period and filters appear under Pinned Views in Stats.")
        }
    }

    private var effectiveSelection: StatsSelection {
        var result = selection
        if !isEyeOpen { result.route = nil }
        return result
    }

    private var detailTitle: Text {
        if metric == .ingestions, let name = effectiveSelection.substance {
            return Text(PersistenceController.shared.displayName(for: name))
        }
        return Text(metric.title)
    }

    private var periodSection: some View {
        Section {
            Picker("Period", selection: $selection.period) {
                ForEach(StatsPeriod.allCases, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
            if selection.period == .custom {
                let now = Date.now
                DatePicker("From", selection: $selection.customStart, in: ...min(selection.customEnd, now), displayedComponents: .date)
                DatePicker("Through", selection: $selection.customEnd, in: min(selection.customStart, now)...now, displayedComponents: .date)
            }
        } footer: {
            if !filterLabels.isEmpty {
                Text(filterLabels.formatted(.list(type: .and)))
            }
        }
    }

    private var filterLabels: [String] {
        var labels: [String] = []
        if metric != .ingestions, let name = selection.substance {
            labels.append(PersistenceController.shared.displayName(for: name))
        }
        if let route = effectiveSelection.route { labels.append(route.rawValue.localizedCapitalized) }
        if let tag = selection.tag { labels.append(tag) }
        switch selection.person {
        case .me: break
        case .everyone: labels.append(String(localized: "Everyone"))
        case .named(let name): labels.append(name)
        }
        return labels
    }

    @ViewBuilder
    private func chartSection(
        records: StatsRecords, buckets: [StatsRecords.Bucket], focused: StatsRecords, selected: StatsRecords.Bucket?
    ) -> some View {
        Section {
            if buckets.isEmpty {
                Text("No entries match this period and filters.")
                    .foregroundStyle(.secondary)
            } else {
                Text(entryCount(records), format: .number)
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                    .accessibilityLabel(Text(metric.title))
                    .accessibilityValue(Text(entryCount(records), format: .number))
                let contributions = metric == .ingestions ? records.ingestionContributions : []
                let colors = Dictionary(records.entries.map {
                    ($0.substanceNameUnwrapped, $0.substanceColor.swiftUIColor)
                }, uniquingKeysWith: { first, _ in first })
                StatsCountChart(
                    buckets: buckets, component: records.bucketComponent,
                    contributions: contributions, colors: colors, selection: $selectedBucket
                )
                NavigationLink {
                    StatsSelectedEntriesScreen(metric: metric, selection: effectiveSelection, selectedBucket: selected)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if selected == nil {
                            Text(metric == .experiences ? "All Experiences" : "All Ingestions")
                        } else {
                            let count = entryCount(focused)
                            if metric == .experiences {
                                Text(count == 1 ? "1 Experience" : "\(count) Experiences")
                            } else {
                                Text(count == 1 ? "1 Ingestion" : "\(count) Ingestions")
                            }
                            Text(rangeLabel(focused.range)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(entryCount(focused) == 0)
            }
        }
    }

    @ViewBuilder
    private func amountsSection(_ records: StatsRecords) -> some View {
        let amounts = records.amounts
        let missingCount = records.unknownAmountCount
        Section {
            if amounts.isEmpty {
                Text("No amounts were recorded for these ingestions.")
                    .foregroundStyle(.secondary)
            }
            ForEach(amounts) { amount in
                DisclosureGroup {
                    LabeledContent("Ingestions", value: amount.count.formatted())
                    LabeledContent("Average", value: formattedAmount(amount.average, unit: amount.key.unit))
                    LabeledContent("Median", value: formattedAmount(amount.median, unit: amount.key.unit))
                    LabeledContent("Lowest", value: formattedAmount(amount.minimum, unit: amount.key.unit))
                    LabeledContent("Highest", value: formattedAmount(amount.maximum, unit: amount.key.unit))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formattedAmount(amount.total, unit: amount.key.unit)).monospacedDigit()
                        if let name = amount.customUnitName {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Recorded Amounts")
        } footer: {
            if !amounts.isEmpty, missingCount > 0 {
                Text("Amounts were recorded for \(records.entries.count - missingCount) of \(records.entries.count) ingestions.")
            }
        }
    }

    private func gapSection(_ gaps: [StatsRecords.Gap]) -> some View {
        Section {
            if gaps.isEmpty {
                Text("No gaps in this selection.").foregroundStyle(.secondary)
            }
            ForEach(gaps) { gap in
                DisclosureGroup {
                    StatsIngestionLink(ingestion: gap.older, timeFormat: .dateTime.month().day().hour().minute())
                    StatsIngestionLink(ingestion: gap.newer, timeFormat: .dateTime.month().day().hour().minute())
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gapDuration(gap.duration))
                            .font(.headline)
                        let first = min(gap.older.timeUnwrapped, gap.newer.timeUnwrapped)
                        let last = max(gap.older.timeUnwrapped, gap.newer.timeUnwrapped)
                        Text((first..<last).formatted(.interval.month(.abbreviated).day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func breakdown(_ records: StatsRecords, tags: [String: PersonalSubstanceTags]) -> some View {
        if !records.entries.isEmpty && selection.substance == nil {
            let groupingByTag = groupsByPrimaryTag
            let byName = Dictionary(grouping: records.entries) { entry -> String? in
                if groupingByTag { return tags[entry.substanceNameUnwrapped]?.primary.map(PersonalSubstanceTags.key) }
                return entry.substanceNameUnwrapped
            }
            let ranked = byName.map { key, entries in
                let label: String
                if groupingByTag {
                    label = entries.first.flatMap { tags[$0.substanceNameUnwrapped]?.primary } ?? String(localized: "No Primary Tag")
                } else {
                    label = key.map { PersistenceController.shared.displayName(for: $0) } ?? ""
                }
                let count = metric == .experiences ? Set(entries.compactMap { $0.experience?.objectID }).count : entries.count
                return (key: key, entries: entries, label: label, count: count)
            }.sorted { a, b in
                substanceOrder.precedes(count: a.count, name: a.label, otherCount: b.count, otherName: b.label)
            }
            let highestCount = ranked.map(\.count).max() ?? 0
            Section {
                if tags.values.contains(where: { $0.primary != nil }) {
                    Picker("Group By", selection: $groupsByPrimaryTag) {
                        Text("Substance").tag(false)
                        Text("Primary Tag").tag(true)
                    }
                }
                ForEach(ranked, id: \.key) { row in
                    let key = row.key
                    let entries = row.entries
                    let count = row.count
                    if groupingByTag {
                        if let key,
                           let entry = entries.first,
                           let tag = tags[entry.substanceNameUnwrapped]?.primary {
                            Button {
                                selection.tag = tag
                                selection.matchesPrimaryTagOnly = true
                            } label: {
                                LabeledContent(tag, value: count.formatted())
                            }
                            .accessibilityIdentifier("stats.primaryTag.\(key)")
                        } else {
                            LabeledContent("No Primary Tag", value: count.formatted())
                        }
                    } else if let key {
                        Button {
                            selection.substance = key
                        } label: {
                            StatsComparisonRow(
                                title: row.label, count: count, highestCount: highestCount,
                                color: entries.first?.substanceColor.swiftUIColor ?? .accentColor
                            )
                        }
                    }
                }
            } header: {
                StatsSubstanceSortHeader(title: groupingByTag ? "Primary Tags" : "Substances", order: $substanceOrder)
            } footer: {
                if metric == .experiences {
                    Text("An experience can include more than one group.")
                }
            }
        }
    }

    private func entryCount(_ records: StatsRecords) -> Int {
        metric == .experiences ? records.experiences.count : records.entries.count
    }

    private func clearHiddenRoute() {
        if !isEyeOpen { selection.route = nil }
    }

    private func pinView() {
        let name = pinName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let pins = StatsPreferences.decode(pinnedStatsData)
        let pin = PinnedStatsView(name: name, metric: metric, selection: effectiveSelection)
        if let data = try? JSONEncoder().encode(pins + [pin]) {
            pinnedStatsData = data
        }
    }

    private func formattedAmount(_ value: Double, unit: String) -> String {
        let amount = value.formatted(.number.precision(.fractionLength(0...6)))
        return unit.isEmpty ? amount : "\(amount) \(unit)"
    }

    private func gapDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return String(localized: "No gap") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? ""
    }
}

private func rangeLabel(_ interval: DateInterval) -> String {
    let end = max(interval.start, interval.end.addingTimeInterval(-0.001))
    return (interval.start..<end).formatted(.interval.year().month(.abbreviated).day())
}

private struct StatsCountChart: View {
    let buckets: [StatsRecords.Bucket]
    let component: Calendar.Component
    let contributions: [StatsRecords.Contribution]
    let colors: [String: Color]
    @Binding var selection: Date?

    var body: some View {
        Chart {
            if contributions.isEmpty {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("Period", bucket.id, unit: component),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(Color.accentColor)
                    .opacity(opacity(for: bucket.id))
                    .accessibilityLabel(Text(rangeLabel(bucket.interval)))
                    .accessibilityValue(Text(bucket.count, format: .number))
                }
            } else {
                ForEach(contributions) { item in
                    BarMark(
                        x: .value("Period", item.id.date, unit: component),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Substance", item.id.substance))
                    .opacity(opacity(for: item.id.date))
                    .accessibilityLabel(Text(PersistenceController.shared.displayName(for: item.id.substance)))
                    .accessibilityValue(Text(item.count, format: .number))
                }
            }
        }
        .chartForegroundStyleScale(mapping: { colors[$0] ?? Color.accentColor })
        .chartLegend(.hidden)
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                    .gesture(SpatialTapGesture().onEnded { tap in
                        let x = tap.location.x - geometry[proxy.plotAreaFrame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        let id = buckets.first { $0.interval.start <= date && date < $0.interval.end }?.id
                        selection = selection == id ? nil : id
                    })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart Period")
        .accessibilityValue(Text(accessiblePeriod))
        .accessibilityAdjustableAction { direction in
            let index = buckets.firstIndex { $0.id == selection }
            switch direction {
            case .increment:
                let next = (index ?? -1) + 1
                if buckets.indices.contains(next) { selection = buckets[next].id }
            case .decrement:
                if let index {
                    selection = index > 0 ? buckets[index - 1].id : nil
                } else {
                    selection = buckets.last?.id
                }
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text("Full Period")) { selection = nil }
    }

    private var accessiblePeriod: String {
        guard let bucket = buckets.first(where: { $0.id == selection }) else {
            return String(localized: "Full Period")
        }
        return "\(rangeLabel(bucket.interval)), \(bucket.count.formatted())"
    }

    private func opacity(for period: Date) -> Double {
        selection == nil || selection == period ? 1 : 0.35
    }
}

private struct StatsSelectedEntriesScreen: View {
    let metric: StatsMetric
    let selection: StatsSelection
    let selectedBucket: StatsRecords.Bucket?

    var body: some View {
        StatsJournal { entries, tags in
            let allRecords = StatsRecords(entries: entries, selection: selection, tags: tags)
            let records = selectedBucket.map { allRecords.selecting($0, for: metric) } ?? allRecords
            List {
                if metric == .experiences {
                    ForEach(records.experiences, id: \.experience.objectID) { match in
                        ExperienceRow(experience: match.experience, timeDisplayStyle: .regular)
                    }
                } else {
                    ForEach(records.entries) { entry in
                        StatsIngestionLink(ingestion: entry, timeFormat: .dateTime.month().day().year().hour().minute())
                    }
                }
                if metric == .experiences ? records.experiences.isEmpty : records.entries.isEmpty {
                    Text("No entries match this selection.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(metric == .experiences ? "Experiences" : "Ingestions")
        }
    }
}

private struct StatsIngestionLink: View {
    @ObservedObject var ingestion: Ingestion
    let timeFormat: Date.FormatStyle
    @State private var isEditing = false
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            IngestionRow(ingestion: ingestion, isEyeOpen: isEyeOpen, isHidingDosageDots: isHidingDosageDots) {
                Text(ingestion.timeUnwrapped, format: timeFormat)
            }
            .foregroundStyle(.primary)
        }
        .sheet(isPresented: $isEditing) {
            EditIngestionScreen(ingestion: ingestion)
        }
    }
}

private struct StatsFiltersScreen: View {
    @Binding var selection: StatsSelection
    let entries: [Ingestion]
    let tagNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let names = Set(entries.map(\.substanceNameUnwrapped)).union([selection.substance].compactMap { $0 })
                    let options = names.map { ($0, PersistenceController.shared.displayName(for: $0)) }
                    let groups = Dictionary(grouping: options, by: { $0.1.lowercased() })
                    NavigationLink {
                        StatsSubstancePicker(selection: $selection.substance, options: options.map { name, label in
                            StatsSubstancePicker.Option(name: name, title: groups[label.lowercased(), default: []].count > 1 && name != label
                                                        ? "\(label) (\(name))" : label)
                        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
                    } label: {
                        LabeledContent("Substance", value: selection.substance.map { PersistenceController.shared.displayName(for: $0) }
                                       ?? String(localized: "All Substances"))
                    }
                    let tags = tagNames.union([selection.tag].compactMap { $0 }).sorted()
                    if !tags.isEmpty {
                        Picker("Tag", selection: Binding(
                            get: { selection.tag },
                            set: { tag in
                                selection.tag = tag
                                selection.matchesPrimaryTagOnly = false
                            }
                        )) {
                            Text("All Tags").tag(nil as String?)
                            ForEach(tags, id: \.self) { tag in Text(tag).tag(Optional(tag)) }
                        }
                    }
                    if isEyeOpen {
                        let routes = Set(entries.map(\.administrationRouteUnwrapped)).union([selection.route].compactMap { $0 })
                        Picker("Route", selection: $selection.route) {
                            Text("All Routes").tag(nil as AdministrationRoute?)
                            ForEach(AdministrationRoute.allCases.filter { routes.contains($0) }) { route in
                                Text(route.rawValue.localizedCapitalized).tag(Optional(route))
                            }
                        }
                    }
                    let consumers = Set(entries.filter { !$0.isMine }.map(\.consumerNameUnwrapped))
                    let selectedPerson: String? = if case .named(let name) = selection.person { name } else { nil }
                    if !consumers.isEmpty || selection.person != .me {
                        Picker("Person", selection: $selection.person) {
                            Text("Me").tag(StatsSelection.Person.me)
                            Text("Everyone").tag(StatsSelection.Person.everyone)
                            ForEach(consumers.union([selectedPerson].compactMap { $0 }).sorted(), id: \.self) { name in
                                Text(name).tag(StatsSelection.Person.named(name))
                            }
                        }
                    }
                }
                if selection.hasFilters {
                    Section {
                        Button("Reset Filters") {
                            selection.substance = nil
                            selection.route = nil
                            selection.person = .me
                            selection.tag = nil
                            selection.matchesPrimaryTagOnly = false
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StatsSubstancePicker: View {
    struct Option: Identifiable {
        var id: String { name }
        let name: String
        let title: String
    }

    @Binding var selection: String?
    let options: [Option]
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            choice("All Substances", name: nil)
            ForEach(options.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { option in
                choice(option.title, name: option.name)
            }
        }
        .searchable(text: $query, prompt: "Search Substances")
        .navigationTitle("Substance")
    }

    private func choice(_ title: String, name: String?) -> some View {
        Button {
            selection = name
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selection == name {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Selected")
                }
            }
        }
    }
}
