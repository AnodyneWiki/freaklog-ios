import Charts
import SwiftUI

struct StatsDetailScreen: View {
    let metric: StatsMetric
    private let isSubstanceHistory: Bool
    @State private var selection: StatsSelection
    @State private var selectedInterval: DateInterval?
    @State private var showsAmounts: Bool
    @State private var isShowingFilters = false
    @State private var selectedAmountKey: StatsRecords.Amount.Key?
    @State private var expandedAmounts: Set<StatsRecords.Amount.Key> = []
    @State private var substanceOrder = StatsSubstanceOrder.count
    @State private var shareSelection: StatsRecords?
    @State private var isNamingView = false
    @State private var pinName = ""
    @State private var selectionToPin: StatsSelection?
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(JournalDay.startHourKey) private var dayStartHour = 0
    @AppStorage(StatsPreferences.pinnedViewsKey) private var pinnedStatsData = Data()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(metric: StatsMetric, selection: StatsSelection, isSubstanceHistory: Bool = false) {
        self.metric = metric == .amounts ? .ingestions : metric
        self.isSubstanceHistory = isSubstanceHistory
        _selection = State(initialValue: selection)
        _showsAmounts = State(initialValue: metric == .amounts)
    }

    var body: some View {
        StatsJournal { entries, tags in
            let now = Date.now
            let records = StatsRecords(
                entries: entries, selection: effectiveSelection, now: now, dayStartHour: dayStartHour, tags: tags
            )
            let neighboring = StatsAdjacentPeriods(
                entries: entries, selection: effectiveSelection, now: now, dayStartHour: dayStartHour, tags: tags
            )
            let buckets = records.buckets(for: metric)
            let focused = selectedInterval.map { records.selecting($0, for: metric) } ?? records
            let scopedSelection = selectedInterval.map { _ in
                let experienceScope = effectiveSelection.focus.flatMap { focus in
                    focus.experienceFilter == nil ? nil : focus.sourceInterval
                }
                return effectiveSelection.focused(
                    on: focused.range, metric: metric,
                    within: experienceScope ?? records.range
                )
            } ?? effectiveSelection
            List {
                periodSection

                if metric != .gaps {
                    if showsAmounts {
                        amountsSection(records, focused: focused, selection: scopedSelection, neighboring: neighboring)
                    } else {
                        chartSection(
                            records: records, buckets: buckets, focused: focused, selection: scopedSelection,
                            tags: tags, neighboring: neighboring
                        )
                    }
                    if let historySubstance {
                        historySections(focused, selection: scopedSelection, substance: historySubstance)
                        unconfirmedSection(entries: entries, tags: tags, range: focused.range, selection: scopedSelection)
                        StatsGoalsSection(entries: entries, substance: historySubstance)
                    } else if !showsAmounts {
                        breakdown(focused, tags: tags, selection: scopedSelection)
                    }
                    if metric == .ingestions, !showsAmounts, isEyeOpen, effectiveSelection.route == nil {
                        routeSection(focused, selection: scopedSelection)
                    }
                    if metric == .ingestions, effectiveSelection.singleSubstance != nil,
                       effectiveSelection.person != .everyone, !focused.entries.isEmpty {
                        Section {
                            NavigationLink {
                                StatsDetailScreen(metric: .gaps, selection: scopedSelection)
                            } label: {
                                Label("Time Between Logs", systemImage: "clock")
                            }
                        }
                    }
                } else if effectiveSelection.singleSubstance != nil && effectiveSelection.person != .everyone {
                    gapSection(focused, journalEntries: entries, selection: scopedSelection)
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
                            selectionToPin = scopedSelection.anchored(now: .now, dayStartHour: dayStartHour)
                            isNamingView = true
                        } label: {
                            Label("Pin View", systemImage: "pin")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                StatsFiltersScreen(
                    selection: $selection, entries: entries,
                    tagNames: Set(tags.values.flatMap(\.names)), selectsSingleSubstance: isSubstanceHistory
                )
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
        .onChange(of: selection.period) { _ in clearFocusedPeriod() }
        .onChange(of: selection.customStart) { _ in clearFocusedPeriod() }
        .onChange(of: selection.customEnd) { _ in clearFocusedPeriod() }
        .onChange(of: selection.periodStep) { _ in clearFocusedPeriod() }
        .onChange(of: selection.entryFilter) { _ in selectedInterval = nil }
        .onChange(of: dayStartHour) { _ in selectedInterval = nil }
        .onChange(of: showsAmounts) { _ in selectedInterval = nil }
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

    private var historySubstance: String? {
        isSubstanceHistory ? selection.singleSubstance : nil
    }

    private var effectiveSelection: StatsSelection {
        var result = selection
        if !isEyeOpen { result.route = nil }
        return result
    }

    private var chartPeriodStep: Binding<Int>? {
        selection.focus == nil && selection.period.canBrowse ? $selection.periodStep : nil
    }

    private var detailTitle: Text {
        if let historySubstance {
            return Text(PersistenceController.shared.displayName(for: historySubstance))
        }
        if let alongside = effectiveSelection.alongside {
            return Text("Logged with \(PersistenceController.shared.displayName(for: alongside))")
        }
        if metric == .ingestions, let name = effectiveSelection.singleSubstance {
            return Text(PersistenceController.shared.displayName(for: name))
        }
        return Text(metric.title)
    }

    private var periodSection: some View {
        Section {
            if let focus = selection.focus {
                Menu {
                    Button("Full Period") { clearFocusedPeriod() }
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(statsRangeLabel(focus.interval, journalDay: .init(startHour: dayStartHour)))
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                    } label: {
                        Text("Period")
                    }
                }
            } else {
                StatsPeriodControls(
                    period: $selection.period, start: $selection.customStart, end: $selection.customEnd,
                    step: $selection.periodStep
                )
            }
        } footer: {
            if !filterLabels.isEmpty {
                Text(filterLabels.formatted(.list(type: .and)))
            }
        }
    }

    private var filterLabels: [String] {
        var labels: [String] = []
        if metric != .ingestions || effectiveSelection.singleSubstance == nil {
            labels += effectiveSelection.substances.sorted().map { PersistenceController.shared.displayName(for: $0) }
        }
        if let route = effectiveSelection.route { labels.append(route.rawValue.localizedCapitalized) }
        labels += selection.tags.sorted()
        if let tag = selection.requiredPrimaryTag, !selection.tags.contains(tag) {
            labels.append(tag)
        }
        switch selection.person {
        case .me: break
        case .everyone: labels.append(String(localized: "Everyone"))
        case .named(let name): labels.append(name)
        }
        return labels
    }

    @ViewBuilder
    private func chartSection(
        records: StatsRecords, buckets: [StatsRecords.Bucket], focused: StatsRecords,
        selection scoped: StatsSelection, tags: [String: PersonalSubstanceTags], neighboring: StatsAdjacentPeriods
    ) -> some View {
        Section {
            if metric == .ingestions { chartMetricPicker }
            if records.entries.contains(where: { tags[$0.substanceNameUnwrapped]?.primary != nil }) {
                Picker("Chart Groups", selection: $selection.groupsByPrimaryTag) {
                    Text(metric == .experiences ? "Total" : "Substance").tag(false)
                    Text("Primary Tag").tag(true)
                }
            }
            let selectedBucket = buckets.first { $0.id == selectedInterval?.start }
            if !buckets.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if metric == .ingestions, effectiveSelection.singleSubstance != nil {
                        Text("Ingestions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(entryCount(focused), format: .number)
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .accessibilityLabel(Text(metric.title))
                        .accessibilityValue(Text(entryCount(focused), format: .number))
                    if selectedInterval != nil || selection.period == .custom {
                        Text(statsRangeLabel(focused.range, journalDay: records.journalDay))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if historySubstance != nil, let latest = focused.entries.compactMap(\.time).max() {
                        Text("Last logged \(latest.formatted(.dateTime.year().month().day().hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                let (contributions, seriesColors, labels) = countSeries(records, tags: tags)
                countChart(
                    records, buckets: buckets, contributions: contributions, colors: seriesColors,
                    labels: labels, tags: tags, neighboring: neighboring
                )
                if selection.groupsByPrimaryTag {
                    let visible = contributions.filter { selectedBucket == nil || $0.id.date == selectedBucket?.id }
                    let series = Dictionary(grouping: visible, by: \.id.substance).mapValues {
                        $0.reduce(0) { $0 + $1.count }
                    }
                    let total = max(series.values.reduce(0, +), 1)
                    ForEach(series.keys.sorted { series[$0, default: 0] > series[$1, default: 0] ||
                        (series[$0] == series[$1] && $0 < $1) }, id: \.self) { name in
                        let count = series[name, default: 0]
                        seriesRow(
                            labels[name] ?? name,
                            value: "\(count.formatted()) · \((Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0))))",
                            color: seriesColors[name] ?? .secondary
                        )
                    }
                } else if let selectedBucket, effectiveSelection.singleSubstance == nil {
                    ForEach(contributions.filter { $0.id.date == selectedBucket.id }) { item in
                        seriesRow(labels[item.id.substance] ?? item.id.substance,
                                  value: item.count.formatted(), color: seriesColors[item.id.substance] ?? .accentColor)
                    }
                }
            } else if chartPeriodStep != nil {
                countChart(
                    records, buckets: [], contributions: [], colors: [:], labels: [:], tags: tags, neighboring: neighboring
                )
            } else {
                Text("No entries match this period and filters.")
                    .foregroundStyle(.secondary)
            }
            if metric == .ingestions {
                StatsCoverageRows(records: focused)
            }
            if !buckets.isEmpty && historySubstance == nil {
                NavigationLink {
                    StatsSelectedEntriesScreen(metric: metric, selection: scoped)
                } label: {
                    if selectedInterval == nil {
                        Text(metric == .experiences ? "All Experiences" : "All Ingestions")
                    } else {
                        Text(metric == .experiences ? "Experiences in Selection" : "Ingestions in Selection")
                    }
                }
                .disabled(entryCount(focused) == 0)
            }
        } footer: {
            if selection.groupsByPrimaryTag, metric == .experiences, !buckets.isEmpty {
                Text("An experience contributes once to the chart. Experiences spanning multiple primary tag groups are grouped together.")
            }
        }
    }

    private func countSeries(
        _ records: StatsRecords, tags: [String: PersonalSubstanceTags]
    ) -> ([StatsRecords.Contribution], [String: Color], [String: String]) {
        if selection.groupsByPrimaryTag {
            let names = Dictionary(records.entries.compactMap { entry -> (String, String)? in
                guard let name = tags[entry.substanceNameUnwrapped]?.primary else { return nil }
                return (PersonalSubstanceTags.key(name), name)
            }, uniquingKeysWith: { first, _ in first })
            let untagged = "\u{0}untagged"
            let mixed = "\u{0}mixed"
            let contributions = records.contributions(for: metric, group: { entry in
                tags[entry.substanceNameUnwrapped]?.primary.map(PersonalSubstanceTags.key) ?? untagged
            }, mixedGroup: mixed)
            let colors = tagColors(names).merging([untagged: .gray, mixed: .secondary]) { first, _ in first }
            let labels = names.merging([
                untagged: String(localized: "No Primary Tag"), mixed: String(localized: "Multiple Groups")
            ]) { first, _ in first }
            return (contributions, colors, labels)
        }
        let colors = Dictionary(records.entries.map {
            ($0.substanceNameUnwrapped, $0.substanceColor.swiftUIColor)
        }, uniquingKeysWith: { first, _ in first })
        let labels = Dictionary(uniqueKeysWithValues: colors.keys.map {
            ($0, PersistenceController.shared.displayName(for: $0))
        })
        return (metric == .ingestions ? records.ingestionContributions : [], colors, labels)
    }

    private func countChart(
        _ records: StatsRecords, buckets: [StatsRecords.Bucket], contributions: [StatsRecords.Contribution],
        colors: [String: Color], labels: [String: String], tags: [String: PersonalSubstanceTags],
        neighboring: StatsAdjacentPeriods
    ) -> some View {
        StatsPeriodPager(step: chartPeriodStep, oldestStep: selection.period.oldestOffset, height: 180) { direction in
            if direction == 0 {
                countPage(records, buckets: buckets, contributions: contributions, colors: colors, labels: labels,
                          selection: Binding(
                              get: { selectedInterval?.start },
                              set: { id in selectedInterval = buckets.first { $0.id == id }?.interval }
                          ))
            } else if let page = neighboring[direction] {
                let (contributions, colors, labels) = countSeries(page, tags: tags)
                countPage(page, buckets: page.buckets(for: metric), contributions: contributions, colors: colors,
                          labels: labels, selection: .constant(nil))
            }
        }
    }

    @ViewBuilder
    private func countPage(
        _ records: StatsRecords, buckets: [StatsRecords.Bucket], contributions: [StatsRecords.Contribution],
        colors: [String: Color], labels: [String: String], selection: Binding<Date?>
    ) -> some View {
        if let domain = records.chartDomain(covering: buckets) {
            StatsPeriodChart(
                buckets: buckets, component: records.bucketComponent, domain: domain, journalDay: records.journalDay,
                contributions: contributions, colors: colors, labels: labels, selection: selection
            )
        } else {
            Text("No entries match this period and filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var chartMetricPicker: some View {
        Picker("Chart Metric", selection: $showsAmounts) {
            Text("Ingestions").tag(false)
            Text("Amounts").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private func tagColors(_ names: [String: String]) -> [String: Color] {
        let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .green, .brown, .cyan]
        return Dictionary(uniqueKeysWithValues: names.keys.sorted().enumerated().map {
            ($0.element, palette[$0.offset % palette.count])
        })
    }

    private func seriesRow(_ name: String, value: String, color: Color) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label {
                Text(name)
            } icon: {
                Circle().fill(color)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func historySections(_ records: StatsRecords, selection: StatsSelection, substance: String) -> some View {
        Section("History") {
            if records.entries.isEmpty {
                Text("No confirmed ingestions in this period.").foregroundStyle(.secondary)
            }
            ForEach(records.entries.prefix(5)) { entry in
                StatsIngestionLink(ingestion: entry, timeFormat: .dateTime.month().day().year().hour().minute())
            }
            if records.entries.count > 5 {
                NavigationLink("All Matching Ingestions") {
                    StatsSelectedEntriesScreen(metric: .ingestions, selection: selection)
                }
            }
            if !records.experiences.isEmpty {
                NavigationLink {
                    StatsDetailScreen(metric: .experiences, selection: selection)
                } label: {
                    Label("Experiences", systemImage: "square.stack")
                }
            }
            NavigationLink {
                JournalCalendarScreen(substanceName: substance, statsSelection: selection)
            } label: {
                Label("Journal Calendar", systemImage: "calendar")
            }
        }
        if !records.experiences.isEmpty {
            Section {
                NavigationLink {
                    StatsDetailScreen(metric: .ingestions, selection: alongsideSelection(selection, substance: substance))
                } label: {
                    Label("Logged Alongside", systemImage: "square.stack")
                }
            }
        }
        if isEyeOpen {
            if let builtIn = SubstanceRepo.shared.getSubstance(name: substance) {
                Section {
                    NavigationLink {
                        SubstanceScreen(substance: builtIn)
                    } label: {
                        Label("Substance Information", systemImage: "info.circle")
                    }
                }
            } else if let customSubstance = PersistenceController.shared.getCustomSubstance(name: substance) {
                Section {
                    NavigationLink {
                        CustomSubstanceScreen(customSubstance: customSubstance)
                    } label: {
                        Label("Substance Information", systemImage: "info.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unconfirmedSection(
        entries: [Ingestion], tags: [String: PersonalSubstanceTags], range: DateInterval, selection: StatsSelection
    ) -> some View {
        let unconfirmed = entries.filter { entry in
            guard entry.isUnconfirmed, let time = entry.time, range.start <= time, time < range.end else { return false }
            let personalTags = tags[entry.substanceNameUnwrapped, default: PersonalSubstanceTags()]
            return selection.includes(entry, tags: personalTags)
        }
        if !unconfirmed.isEmpty {
            DisclosureGroup("Unconfirmed Ingestions (\(unconfirmed.count))") {
                ForEach(unconfirmed) { entry in
                    StatsIngestionLink(ingestion: entry, timeFormat: .dateTime.month().day().year().hour().minute())
                }
            }
        }
    }

    private func alongsideSelection(_ selection: StatsSelection, substance: String) -> StatsSelection {
        var result = selection
        result.alongside = substance
        result.alongsideFilter = selection.entryFilter
        result.substances = []
        result.route = nil
        result.tags = []
        result.requiredPrimaryTag = nil
        result.matchesPrimaryTagOnly = false
        return result
    }

    private func amountsSection(
        _ records: StatsRecords, focused: StatsRecords, selection scoped: StatsSelection, neighboring: StatsAdjacentPeriods
    ) -> some View {
        let amounts = records.amounts
        let trends = records.amountTrends
        let previousTrends = neighboring[-1]?.amountTrends
        let nextTrends = neighboring[1]?.amountTrends
        let domain = records.chartDomain(covering: records.buckets(for: .ingestions))
        let colors = Dictionary(records.entries.map {
            ($0.substanceNameUnwrapped, $0.substanceColor.swiftUIColor)
        }, uniquingKeysWith: { first, _ in first })

        return Group {
            Section {
                chartMetricPicker
            }

            Section {
                if amounts.isEmpty {
                    Text("No amounts were recorded for these ingestions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(amounts) { amount in
                    let isSelected = selectedAmountKey == amount.key && selectedInterval != nil
                    let summary = isSelected ? focused.amounts.first { $0.key == amount.key } ?? amount : amount
                    let buckets = trends[amount.key] ?? []
                    let color = colors[amount.key.substance] ?? .accentColor

                    if amounts.count == 1 {
                        amountTotal(summary, prominent: true)
                        amountChart(
                            amount, buckets: buckets, domain: domain, records: records, focused: focused, color: color,
                            neighboring: neighboring, previous: previousTrends?[amount.key] ?? [], next: nextTrends?[amount.key] ?? []
                        )
                        matchingAmountsLink(summary, selection: isSelected ? scoped : effectiveSelection)
                        DisclosureGroup("Amount Details") {
                            amountDetails(summary)
                        }
                    } else {
                        DisclosureGroup(isExpanded: amountExpansion(for: amount.key)) {
                            amountChart(
                                amount, buckets: buckets, domain: domain, records: records, focused: focused, color: color,
                                neighboring: neighboring, previous: previousTrends?[amount.key] ?? [],
                                next: nextTrends?[amount.key] ?? []
                            )
                            matchingAmountsLink(summary, selection: isSelected ? scoped : effectiveSelection)
                            amountDetails(summary)
                        } label: {
                            HStack(spacing: 12) {
                                amountTotal(summary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !expandedAmounts.contains(amount.key), !dynamicTypeSize.isAccessibilitySize, let domain {
                                    StatsAmountTrendPreview(
                                        buckets: buckets, component: records.bucketComponent, domain: domain,
                                        journalDay: records.journalDay, color: color
                                    )
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Recorded Amounts")
            } footer: {
                if !amounts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Amounts were recorded for \(records.entries.count - records.unknownAmountCount) of \(records.entries.count) ingestions.")
                        Text("Each chart has its own scale. Mass is shown in milligrams, and custom units stay separate.")
                    }
                }
            }
        }
    }

    private func amountExpansion(for key: StatsRecords.Amount.Key) -> Binding<Bool> {
        Binding {
            expandedAmounts.contains(key)
        } set: { isExpanded in
            if isExpanded {
                expandedAmounts.insert(key)
            } else {
                expandedAmounts.remove(key)
                if selectedAmountKey == key { selectedInterval = nil }
            }
        }
    }

    private func amountTotal(_ amount: StatsRecords.Amount, prominent: Bool = false) -> some View {
        let name = PersistenceController.shared.displayName(for: amount.key.substance)
        return VStack(alignment: .leading, spacing: 4) {
            if let customUnitName = amount.customUnitName {
                Text("\(name) (\(customUnitName))")
            } else {
                Text(name)
            }
            Text(formattedAmount(amount.total, unit: amount.key.unit))
                .font(prominent ? .largeTitle.weight(.semibold) : .subheadline)
                .monospacedDigit()
                .foregroundStyle(prominent ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func amountChart(
        _ amount: StatsRecords.Amount, buckets: [StatsRecords.AmountBucket], domain: ClosedRange<Date>?,
        records: StatsRecords, focused: StatsRecords, color: Color, neighboring: StatsAdjacentPeriods,
        previous: [StatsRecords.AmountBucket], next: [StatsRecords.AmountBucket]
    ) -> some View {
        if selectedAmountKey == amount.key, selectedInterval != nil {
            Text(statsRangeLabel(focused.range, journalDay: records.journalDay))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        StatsPeriodPager(step: chartPeriodStep, oldestStep: selection.period.oldestOffset, height: 180) { direction in
            if direction == 0 {
                amountPage(amount, buckets: buckets, domain: domain, records: records, color: color, selection: Binding(
                    get: { selectedAmountKey == amount.key ? selectedInterval?.start : nil },
                    set: { id in
                        selectedAmountKey = amount.key
                        selectedInterval = buckets.first { $0.id == id }?.interval
                    }
                ))
            } else if let page = neighboring[direction] {
                amountPage(
                    amount, buckets: direction < 0 ? previous : next,
                    domain: page.chartDomain(covering: page.buckets(for: .ingestions)),
                    records: page, color: color, selection: .constant(nil)
                )
            }
        }
    }

    @ViewBuilder
    private func amountPage(
        _ amount: StatsRecords.Amount, buckets: [StatsRecords.AmountBucket], domain: ClosedRange<Date>?,
        records: StatsRecords, color: Color, selection: Binding<Date?>
    ) -> some View {
        if let domain, !buckets.isEmpty {
            StatsPeriodChart(
                buckets: buckets.map { StatsRecords.Bucket(interval: $0.interval, count: 0) },
                component: records.bucketComponent, domain: domain, journalDay: records.journalDay,
                contributions: [], colors: [:], labels: [:],
                amounts: Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0.total) }),
                amountUnit: amount.key.unit, amountColor: color, selection: selection
            )
        } else {
            Text("No amounts recorded for this period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func matchingAmountsLink(_ amount: StatsRecords.Amount, selection: StatsSelection) -> some View {
        NavigationLink {
            StatsSelectedEntriesScreen(metric: .ingestions, selection: selection, amountKey: amount.key)
        } label: {
            LabeledContent("Matching Ingestions", value: amount.count.formatted())
        }
    }

    @ViewBuilder
    private func amountDetails(_ amount: StatsRecords.Amount) -> some View {
        LabeledContent("Average per Ingestion", value: formattedAmount(amount.average, unit: amount.key.unit))
        LabeledContent("Median per Ingestion", value: formattedAmount(amount.median, unit: amount.key.unit))
        LabeledContent("Lowest", value: formattedAmount(amount.minimum, unit: amount.key.unit))
        LabeledContent("Highest", value: formattedAmount(amount.maximum, unit: amount.key.unit))
        if let average = amount.experienceAverage {
            LabeledContent("Experiences with Amounts", value: amount.experienceCount.formatted())
            LabeledContent("Average per Experience", value: formattedAmount(average, unit: amount.key.unit))
        }
    }

    @ViewBuilder
    private func routeSection(_ records: StatsRecords, selection scoped: StatsSelection) -> some View {
        let recorded = records.entries.compactMap(StatsRecords.recordedRoute)
        let routes = Dictionary(grouping: recorded, by: { $0 }).mapValues(\.count)
        let unknownCount = records.entries.count - recorded.count
        let ranked = routes.keys.sorted {
            let lhs = routes[$0, default: 0], rhs = routes[$1, default: 0]
            return lhs == rhs ? $0.rawValue < $1.rawValue : lhs > rhs
        }
        if !records.entries.isEmpty {
            Section("Routes") {
                ForEach(ranked, id: \.self) { route in
                    NavigationLink {
                        StatsDetailScreen(metric: .ingestions, selection: routeSelection(scoped, route: route))
                    } label: {
                        StatsComparisonRow(
                            title: route.rawValue.localizedCapitalized, count: routes[route, default: 0],
                            highestCount: routes[ranked[0], default: 0], color: .teal
                        )
                    }
                }
                if unknownCount > 0 {
                    LabeledContent("Unspecified", value: unknownCount.formatted())
                }
            }
        }
    }

    private func routeSelection(_ selection: StatsSelection, route: AdministrationRoute) -> StatsSelection {
        var copy = selection
        copy.route = route
        return copy
    }

    @ViewBuilder
    private func gapSection(_ records: StatsRecords, journalEntries: [Ingestion], selection scoped: StatsSelection) -> some View {
        let gaps = records.gapsBetweenLogs
        let reference = scoped.singleSubstance.flatMap { SubstanceRepo.shared.getSubstance(name: $0) }
        let usesUnfilteredHistory = scoped.route == nil && scoped.alongside == nil
        let duration = isEyeOpen && usesUnfilteredHistory
            ? reference?.tolerance?.zeroToleranceInHours.map { $0 * 3_600 }
                .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            : nil
        let now = Date.now
        if usesUnfilteredHistory, let latest = latestLog(for: scoped, in: journalEntries, through: now),
           records.entries.contains(latest) {
            Section("Current Gap") {
                let elapsed = now.timeIntervalSince(latest.timeUnwrapped)
                LabeledContent("Time Since Last Log", value: gapDuration(elapsed))
                StatsIngestionLink(ingestion: latest, timeFormat: .dateTime.month().day().year().hour().minute())
                if let duration {
                    referenceProgress(elapsed: elapsed, window: duration)
                }
            }
        }
        if !gaps.isEmpty {
            let durations = gaps.map(\.duration).sorted()
            let midpoint = durations.count / 2
            let median = durations.count.isMultiple(of: 2)
                ? (durations[midpoint - 1] + durations[midpoint]) / 2
                : durations[midpoint]
            Section("Summary") {
                LabeledContent("Median Gap", value: gapDuration(median))
                if let maximum = durations.last {
                    LabeledContent("Longest Gap", value: gapDuration(maximum))
                }
            }
        }
        Section {
            if gaps.isEmpty {
                Text("No gaps in this selection.").foregroundStyle(.secondary)
            }
            ForEach(gaps) { gap in
                DisclosureGroup {
                    StatsIngestionLink(ingestion: gap.older, timeFormat: .dateTime.month().day().hour().minute())
                    StatsIngestionLink(ingestion: gap.newer, timeFormat: .dateTime.month().day().hour().minute())
                    if let duration {
                        referenceProgress(elapsed: gap.duration, window: duration)
                    }
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
        } header: {
            Text("Logged Gaps")
        } footer: {
            if let reference, duration != nil {
                Text("Estimated windows use general \(reference.referenceSource.title) information. They measure time between matching logs and cannot establish your tolerance.")
                if let url = reference.url {
                    Link("Read Source", destination: url)
                }
            }
        }
    }

    private func latestLog(for selection: StatsSelection, in entries: [Ingestion], through now: Date) -> Ingestion? {
        entries.filter {
            !$0.isUnconfirmed && $0.substanceNameUnwrapped == selection.singleSubstance &&
                selection.entryFilter.includesPerson($0) && ($0.time.map { $0 <= now } == true)
        }.max { $0.timeUnwrapped < $1.timeUnwrapped }
    }

    private func referenceProgress(elapsed: TimeInterval, window: TimeInterval) -> some View {
        let progress = min(elapsed / window, 1)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress) {
                Text("Estimated Window Elapsed")
            } currentValueLabel: {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
            Text("\(gapDuration(window)) reference window")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func breakdown(
        _ records: StatsRecords, tags: [String: PersonalSubstanceTags], selection scoped: StatsSelection
    ) -> some View {
        if !records.entries.isEmpty && selection.singleSubstance == nil {
            let groupingByTag = selection.groupsByPrimaryTag
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
                ForEach(ranked, id: \.key) { row in
                    let key = row.key
                    let entries = row.entries
                    let count = row.count
                    if groupingByTag {
                        if let key,
                           let entry = entries.first,
                           let tag = tags[entry.substanceNameUnwrapped]?.primary {
                            NavigationLink {
                                StatsDetailScreen(metric: metric, selection: primaryTagSelection(scoped, tag: tag))
                            } label: {
                                LabeledContent(tag, value: count.formatted())
                            }
                            .accessibilityIdentifier("stats.primaryTag.\(key)")
                        } else {
                            LabeledContent("No Primary Tag", value: count.formatted())
                        }
                    } else if let key {
                        NavigationLink {
                            SubstanceHistoryScreen(substanceName: key, selection: scoped.forSubstance(key))
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

    private func primaryTagSelection(_ selection: StatsSelection, tag: String) -> StatsSelection {
        var result = selection
        result.requiredPrimaryTag = tag
        return result
    }

    private func entryCount(_ records: StatsRecords) -> Int {
        metric == .experiences ? records.experiences.count : records.entries.count
    }

    private func clearHiddenRoute() {
        if !isEyeOpen { selection.route = nil }
    }

    private func clearFocusedPeriod() {
        selectedInterval = nil
        selection.focus = nil
    }

    private func pinView() {
        let name = pinName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let selectionToPin else { return }
        let pins = StatsPreferences.decode(pinnedStatsData)
        let pin = PinnedStatsView(name: name, metric: showsAmounts ? .amounts : metric, selection: selectionToPin)
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

func statsRangeLabel(_ interval: DateInterval, journalDay: JournalDay) -> String {
    let start = journalDay.label(for: interval.start)
    let end = journalDay.lastLabel(in: interval)
    return (start..<end).formatted(.interval.year().month(.abbreviated).day())
}

private struct StatsAmountTrendPreview: View {
    let buckets: [StatsRecords.AmountBucket]
    let component: Calendar.Component
    let domain: ClosedRange<Date>
    let journalDay: JournalDay
    let color: Color

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Period", journalDay.label(for: bucket.id), unit: component),
                y: .value("Amount", bucket.total)
            )
            .foregroundStyle(color)
        }
        .chartXScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: 64, height: 26)
        .accessibilityHidden(true)
    }
}

private struct StatsPeriodChart: View {
    let buckets: [StatsRecords.Bucket]
    let component: Calendar.Component
    let domain: ClosedRange<Date>
    let journalDay: JournalDay
    let contributions: [StatsRecords.Contribution]
    let colors: [String: Color]
    let labels: [String: String]
    var amounts: [Date: Double]? = nil
    var amountUnit = ""
    var amountColor: Color = .accentColor
    @Binding var selection: Date?

    var body: some View {
        Chart {
            if let amounts {
                ForEach(buckets) { bucket in
                    if let amount = amounts[bucket.id] {
                        BarMark(
                            x: .value("Period", journalDay.label(for: bucket.id), unit: component),
                            y: .value("Amount", amount)
                        )
                        .foregroundStyle(amountColor)
                        .opacity(opacity(for: bucket.id))
                        .accessibilityLabel(Text(statsRangeLabel(bucket.interval, journalDay: journalDay)))
                        .accessibilityValue(Text(amountValue(amount)))
                    }
                }
            } else if contributions.isEmpty {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("Period", journalDay.label(for: bucket.id), unit: component),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(Color.accentColor)
                    .opacity(opacity(for: bucket.id))
                    .accessibilityLabel(Text(statsRangeLabel(bucket.interval, journalDay: journalDay)))
                    .accessibilityValue(Text(bucket.count, format: .number))
                }
            } else {
                ForEach(contributions) { item in
                    BarMark(
                        x: .value("Period", journalDay.label(for: item.id.date), unit: component),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Substance", item.id.substance))
                    .opacity(opacity(for: item.id.date))
                    .accessibilityLabel(Text(seriesLabel(item)))
                    .accessibilityValue(Text(item.count, format: .number))
                }
            }
        }
        .chartXScale(domain: domain)
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
                        let day = journalDay.start(of: date)
                        let id = buckets.first { $0.interval.start <= day && day < $0.interval.end }?.id
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
        let value = amounts?[bucket.id].map(amountValue) ?? bucket.count.formatted()
        return "\(statsRangeLabel(bucket.interval, journalDay: journalDay)), \(value)"
    }

    private func seriesLabel(_ item: StatsRecords.Contribution) -> String {
        let name = labels[item.id.substance] ?? item.id.substance
        guard let bucket = buckets.first(where: { $0.id == item.id.date }) else { return name }
        return "\(name), \(statsRangeLabel(bucket.interval, journalDay: journalDay))"
    }

    private func amountValue(_ amount: Double) -> String {
        let value = amount.formatted(.number.precision(.fractionLength(0...6)))
        return amountUnit.isEmpty ? value : "\(value) \(amountUnit)"
    }

    private func opacity(for period: Date) -> Double {
        selection == nil || selection == period ? 1 : 0.35
    }
}

struct StatsSelectedEntriesScreen: View {
    let metric: StatsMetric
    let selection: StatsSelection
    var amountKey: StatsRecords.Amount.Key? = nil
    @AppStorage(JournalDay.startHourKey) private var dayStartHour = 0

    var body: some View {
        StatsJournal { entries, tags in
            let records = StatsRecords(entries: entries, selection: selection, dayStartHour: dayStartHour, tags: tags)
            let matchingEntries = amountKey.map { key in
                records.entries.filter { StatsRecords.Amount.Key($0) == key && key.value(for: $0) != nil }
            } ?? records.entries
            List {
                if metric == .experiences {
                    ForEach(records.experiences, id: \.experience.objectID) { match in
                        Section {
                            ExperienceRow(experience: match.experience, timeDisplayStyle: .regular)
                            let amounts = StatsRecords.amounts(in: match.entries)
                            if !amounts.isEmpty {
                                DisclosureGroup("Matching Amounts") {
                                    ForEach(amounts) { amount in
                                        LabeledContent {
                                            let number = amount.total.formatted(.number.precision(.fractionLength(0...6)))
                                            Text(amount.key.unit.isEmpty ? number : "\(number) \(amount.key.unit)")
                                                .monospacedDigit()
                                        } label: {
                                            let name = PersistenceController.shared.displayName(for: amount.key.substance)
                                            if let unit = amount.customUnitName {
                                                Text("\(name) (\(unit))")
                                            } else {
                                                Text(name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if !matchingEntries.isEmpty {
                    Section {
                        LabeledContent("Ingestions", value: matchingEntries.count.formatted())
                        if amountKey == nil {
                            StatsCoverageRows(records: records)
                        }
                    }
                    let days = Dictionary(grouping: matchingEntries) { records.journalDay.label(for: $0.timeUnwrapped) }
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        Section {
                            ForEach(days[day] ?? []) { entry in
                                StatsIngestionLink(ingestion: entry, timeFormat: .dateTime.hour().minute())
                            }
                        } header: {
                            Text(day, format: .dateTime.weekday(.wide).day().month().year())
                        }
                    }
                }
                if metric == .experiences ? records.experiences.isEmpty : matchingEntries.isEmpty {
                    Text("No entries match this selection.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(metric == .experiences ? "Experiences" : "Ingestions")
        }
    }
}

struct StatsIngestionLink: View {
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

struct StatsFiltersScreen: View {
    @Binding var selection: StatsSelection
    let entries: [Ingestion]
    let tagNames: Set<String>
    var selectsSingleSubstance = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let substanceTitle: LocalizedStringKey = selectsSingleSubstance ? "Substance" : "Substances"
                    NavigationLink {
                        StatsFilterPicker(
                            title: substanceTitle, searchPrompt: "Search Substances", selection: $selection.substances,
                            options: substanceOptions, selectsOne: selectsSingleSubstance
                        )
                    } label: {
                        LabeledContent(substanceTitle) {
                            summary(selection.substances, all: "All Substances", transform: PersistenceController.shared.displayName(for:))
                        }
                    }
                    let tags = tagNames.union(selection.tags).sorted()
                    if !tags.isEmpty {
                        NavigationLink {
                            StatsFilterPicker(title: "Tags", searchPrompt: "Search Tags", selection: $selection.tags,
                                                options: tags.map { .init(name: $0, title: $0) })
                        } label: {
                            LabeledContent("Tags") {
                                summary(selection.tags, all: "All Tags", transform: { $0 })
                            }
                        }
                        if !selection.tags.isEmpty {
                            Toggle("Primary Tags Only", isOn: $selection.matchesPrimaryTagOnly)
                        }
                    }
                    if isEyeOpen {
                        let routes = Set(entries.compactMap(StatsRecords.recordedRoute))
                            .union([selection.route].compactMap { $0 })
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
                if hasResettableFilters {
                    Section {
                        Button("Reset Filters") {
                            if !selectsSingleSubstance { selection.substances = [] }
                            selection.route = nil
                            selection.person = .me
                            selection.tags = []
                            selection.matchesPrimaryTagOnly = false
                            selection.requiredPrimaryTag = nil
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

    private var substanceOptions: [StatsFilterPicker.Option] {
        var names = Set(entries.map(\.substanceNameUnwrapped)).union(selection.substances)
        names.remove("")
        if selectsSingleSubstance, let alongside = selection.alongside { names.remove(alongside) }
        let options = names.map { ($0, PersistenceController.shared.displayName(for: $0)) }
        let groups = Dictionary(grouping: options, by: { $0.1.lowercased() })
        return options.map { name, label in
            StatsFilterPicker.Option(
                name: name, title: groups[label.lowercased(), default: []].count > 1 && name != label ? "\(label) (\(name))" : label
            )
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var hasResettableFilters: Bool {
        var filters = selection
        if selectsSingleSubstance { filters.substances = [] }
        return filters.hasFilters
    }

    private func summary(
        _ selected: Set<String>, all: LocalizedStringKey, transform: (String) -> String
    ) -> Text {
        if selected.isEmpty { return Text(all) }
        if selected.count == 1, let value = selected.first { return Text(transform(value)) }
        return Text("\(selected.count) Selected")
    }
}

private struct StatsFilterPicker: View {
    struct Option: Identifiable {
        var id: String { name }
        let name: String
        let title: String
    }

    let title: LocalizedStringKey
    let searchPrompt: LocalizedStringKey
    @Binding var selection: Set<String>
    let options: [Option]
    var selectsOne = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if !selectsOne, !selection.isEmpty {
                Button("Clear Selection") { selection.removeAll() }
            }
            ForEach(options.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { option in
                if selectsOne {
                    Button {
                        selection = [option.name]
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer()
                            if selection.contains(option.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(option.name) ? .isSelected : [])
                } else {
                    Toggle(isOn: Binding(
                        get: { selection.contains(option.name) },
                        set: { isSelected in
                            if isSelected {
                                selection.insert(option.name)
                            } else {
                                selection.remove(option.name)
                            }
                        }
                    )) {
                        Text(option.title)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(searchPrompt))
        .navigationTitle(title)
    }
}
