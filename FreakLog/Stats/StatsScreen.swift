import Charts
import Combine
import CoreData
import SwiftUI

struct StatsScreen: View {
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(StatsPreferences.periodKey) private var period: StatsPeriod = .last12Months
    @AppStorage(StatsPreferences.customStartKey)
    private var customStart = StatsSelection().customStart.timeIntervalSinceReferenceDate
    @AppStorage(StatsPreferences.customEndKey)
    private var customEnd = StatsSelection().customEnd.timeIntervalSinceReferenceDate
    @State private var showsAllSubstances = false
    @State private var substanceOrder = StatsSubstanceOrder.count
    @State private var filters = StatsSelection()
    @State private var periodStep = 0
    @State private var showingFilters = false
    @AppStorage(StatsPreferences.pinnedViewsKey) private var pinnedStatsData = Data()
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    private var substanceCompanions: FetchedResults<SubstanceCompanion>

    var body: some View {
        StatsJournal { entries, tags in
            let selection = overviewSelection
            let records = StatsRecords(entries: entries, selection: selection, tags: tags)
            let pins = StatsPreferences.decode(pinnedStatsData)

            List {
                Section {
                    StatsPeriodControls(
                        period: $period, start: dateBinding($customStart), end: dateBinding($customEnd), step: $periodStep
                    )
                } footer: {
                    if !selection.substances.isEmpty {
                        let names = selection.substances.map(PersistenceController.shared.displayName(for:))
                            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                        Text(names.formatted(.list(type: .and)))
                    }
                }

                Section("Summary") {
                    ingestionOverview(records: records, selection: selection)
                    NavigationLink {
                        StatsDetailScreen(metric: .experiences, selection: selection)
                    } label: {
                        LabeledContent {
                            Text(records.experiences.count, format: .number).monospacedDigit()
                        } label: {
                            Label("Experiences", systemImage: "square.stack")
                        }
                    }
                    LabeledContent("Days Logged", value: records.daysLogged.formatted())
                }

                let counts = Dictionary(grouping: records.entries, by: \.substanceNameUnwrapped).mapValues(\.count)
                let ranked = counts.keys.sorted {
                    substanceOrder.precedes(
                        count: counts[$0, default: 0], name: PersistenceController.shared.displayName(for: $0),
                        otherCount: counts[$1, default: 0], otherName: PersistenceController.shared.displayName(for: $1)
                    )
                }
                if !ranked.isEmpty {
                    let highestCount = counts.values.max() ?? 0
                    Section {
                        ForEach(ranked.prefix(showsAllSubstances ? ranked.count : 4), id: \.self) { name in
                            NavigationLink {
                                SubstanceHistoryScreen(substanceName: name, selection: selection)
                            } label: {
                                StatsComparisonRow(
                                    title: PersistenceController.shared.displayName(for: name),
                                    count: counts[name, default: 0], highestCount: highestCount,
                                    color: colors[name] ?? .accentColor
                                )
                            }
                        }
                        if ranked.count > 4 {
                            Button(showsAllSubstances ? "Show Fewer" : "Show All \(ranked.count) Substances") {
                                withAnimation { showsAllSubstances.toggle() }
                            }
                        }
                    } header: {
                        StatsSubstanceSortHeader(title: "Ingestions by Substance", order: $substanceOrder)
                    }
                }

                if !pins.isEmpty {
                    Section("Pinned Views") {
                        ForEach(pins) { pin in
                            NavigationLink {
                                StatsDetailScreen(metric: pin.metric, selection: pin.selection)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(pin.name, systemImage: "pin")
                                    if let focus = pin.selection.focus {
                                        Text(statsRangeLabel(focus.interval))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else if pin.selection.period == .custom {
                                        Text(statsRangeLabel(pin.selection.dateRange(now: .now)))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(pin.selection.period.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    unpin(pin, pins: pins)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                }

                Section("Explore") {
                    NavigationLink {
                        StatsDetailScreen(metric: .ingestions, selection: StatsSelection(period: .last7Days))
                    } label: {
                        Label("Recently Logged", systemImage: "clock")
                    }
                    NavigationLink {
                        StatsDetailScreen(metric: .ingestions, selection: StatsSelection(period: .thisMonth))
                    } label: {
                        Label("This Month", systemImage: "calendar")
                    }
                }

                StatsGoalsSection(entries: entries)

                if isEyeOpen {
                    toleranceSection(entries: entries)
                }
            }
            .navigationTitle("Your Stats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingFilters = true } label: {
                        Label("Filters", systemImage: selection.hasFilters
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                StatsFiltersScreen(
                    selection: $filters, entries: entries,
                    tagNames: Set(tags.values.flatMap(\.names))
                )
            }
        }
    }

    private var overviewSelection: StatsSelection {
        var selection = filters
        selection.period = period
        selection.customStart = Date(timeIntervalSinceReferenceDate: customStart)
        selection.customEnd = Date(timeIntervalSinceReferenceDate: customEnd)
        selection.periodStep = periodStep
        if !isEyeOpen { selection.route = nil }
        return selection
    }

    private func dateBinding(_ timestamp: Binding<Double>) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: timestamp.wrappedValue) },
            set: { timestamp.wrappedValue = $0.timeIntervalSinceReferenceDate }
        )
    }

    private var colors: [String: Color] {
        Dictionary(substanceCompanions.map { ($0.substanceNameUnwrapped, $0.color.swiftUIColor) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func ingestionOverview(records: StatsRecords, selection: StatsSelection) -> some View {
        let contributions = records.ingestionContributions
        let buckets = records.buckets(for: .ingestions)
        return NavigationLink {
            StatsDetailScreen(metric: .ingestions, selection: selection)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("Ingestions", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(records.entries.count, format: .number)
                    .font(.title2.weight(.semibold).monospacedDigit())
                if let domain = records.chartDomain(covering: buckets) {
                    Chart(contributions) { item in
                        BarMark(x: .value("Period", item.id.date, unit: records.bucketComponent),
                                y: .value("Count", item.count))
                            .foregroundStyle(by: .value("Substance", item.id.substance))
                    }
                    .chartXScale(domain: domain)
                    .chartForegroundStyleScale(mapping: { colors[$0] ?? Color.accentColor })
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 54)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func toleranceSection(entries: [Ingestion]) -> some View {
        let now = Date.now
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) ?? now
        let days = entries.compactMap { entry -> SubstanceAndDay? in
            guard entry.isMine, !entry.isUnconfirmed, let time = entry.time, from <= time, time <= now else { return nil }
            return SubstanceAndDay(substanceName: entry.substanceNameUnwrapped, day: time)
        }
        let chart = ExperienceLogic.chartData(for: days, substanceCompanions: Array(substanceCompanions))
        Section {
            NavigationLink(value: GlobalNavigationDestination.toleranceChart) {
                ToleranceChartOverView(toleranceWindows: chart.toleranceWindows)
            }
        } header: {
            Text("Current Tolerance")
        } footer: {
            if !chart.namesOfSubstancesWithMissingTolerance.isEmpty {
                Text("Excluding ") + Text(chart.namesOfSubstancesWithMissingTolerance, format: .list(type: .and))
            }
        }
    }

    private func unpin(_ pin: PinnedStatsView, pins: [PinnedStatsView]) {
        if let data = try? JSONEncoder().encode(pins.filter { $0.id != pin.id }) {
            pinnedStatsData = data
        }
    }
}

enum StatsSubstanceOrder: String, CaseIterable, Identifiable {
    case count, name

    var id: Self { self }
    var title: LocalizedStringKey { self == .count ? "Most Logged" : "Name" }

    func precedes(count: Int, name: String, otherCount: Int, otherName: String) -> Bool {
        if self == .count && count != otherCount { return count > otherCount }
        return name.localizedStandardCompare(otherName) == .orderedAscending
    }
}

struct StatsSubstanceSortHeader: View {
    let title: LocalizedStringKey
    @Binding var order: StatsSubstanceOrder

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                Picker("Sort By", selection: $order) {
                    ForEach(StatsSubstanceOrder.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            } label: {
                Label(order.title, systemImage: "chevron.up.chevron.down")
            }
            .textCase(nil)
            .accessibilityLabel("Sort")
            .accessibilityValue(Text(order.title))
        }
    }
}

struct StatsComparisonRow: View {
    let title: String
    let count: Int
    let highestCount: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(count, format: .number).monospacedDigit()
            } label: {
                Text(title)
            }
            if highestCount > 0 {
                GeometryReader { geometry in
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(count) / CGFloat(highestCount))
                }
                .frame(height: 9)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

enum StatsPreferences {
    static let periodKey = "statsSummaryPeriod"
    static let customStartKey = "statsSummaryCustomStart"
    static let customEndKey = "statsSummaryCustomEnd"
    static let pinnedViewsKey = "pinnedStatsViews"
    static let goalsKey = "statsTrackingGoals"

    static func decode(_ data: Data) -> [PinnedStatsView] {
        (try? JSONDecoder().decode([PinnedStatsView].self, from: data)) ?? []
    }

    static func decodeGoals(_ data: Data) -> [StatsGoal] {
        ((try? JSONDecoder().decode([StatsGoal].self, from: data)) ?? []).filter(\.isValid)
    }
}

struct StatsGoalsSection: View {
    let entries: [Ingestion]
    var substance: String?

    @AppStorage(StatsPreferences.goalsKey) private var data = Data()
    @State private var draft: StatsGoalDraft?

    var body: some View {
        let goals = StatsPreferences.decodeGoals(data)
        let visible = goals.filter { substance == nil || $0.substance == substance }
        let substances = goalSubstances(entries: entries, existing: goals, current: substance)
        Section("Tracking Goals") {
            ForEach(visible) { goal in
                NavigationLink {
                    StatsGoalDetail(goalID: goal.id, fixedSubstance: substance != nil)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PersistenceController.shared.displayName(for: goal.substance))
                        StatsGoalSummary(goal: goal, progress: goal.progress(in: entries, endingAt: .now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove Goal", role: .destructive) { save(goals.filter { $0.id != goal.id }) }
                }
            }
            Button {
                draft = StatsGoalDraft(StatsGoal(substance: substance ?? ""))
            } label: {
                Label("Add Tracking Goal", systemImage: "plus")
            }
            .sheet(item: $draft) { draft in
                StatsGoalEditor(draft: draft, entries: entries, substances: substances, fixedSubstance: substance != nil) {
                    save(StatsPreferences.decodeGoals(data) + [$0])
                }
            }
        }
    }

    private func save(_ goals: [StatsGoal]) {
        if let encoded = try? JSONEncoder().encode(goals) {
            data = encoded
        }
    }
}

private func goalSubstances(entries: [Ingestion], existing: [StatsGoal], current: String? = nil) -> [String] {
    let names = entries.map(\.substanceNameUnwrapped) + existing.map(\.substance) + [current].compactMap { $0 }
    return Set(names.filter { !$0.isEmpty }).sorted {
        PersistenceController.shared.displayName(for: $0)
            .localizedStandardCompare(PersistenceController.shared.displayName(for: $1)) == .orderedAscending
    }
}

private struct StatsGoalDetail: View {
    let goalID: UUID
    let fixedSubstance: Bool
    @AppStorage(StatsPreferences.goalsKey) private var data = Data()
    @State private var draft: StatsGoalDraft?

    var body: some View {
        StatsJournal { entries, _ in
            let goals = StatsPreferences.decodeGoals(data)
            let goal = goals.first { $0.id == goalID }
            List {
                if let current = goal {
                    let progress = current.progress(in: entries, endingAt: .now)
                    Section {
                        StatsGoalSummary(goal: current, progress: progress)
                        ProgressView(value: min(progress.value / current.target, 1))
                            .accessibilityLabel("Progress toward your tracking goal")
                    } header: {
                        Text("Last \(current.days) Days")
                    } footer: {
                        if current.metric == .amount, progress.entries.contains(where: \.isEstimate) {
                            Text("Includes recorded estimates.")
                        }
                    }
                    Section("Counted Ingestions") {
                        if progress.entries.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                        rows(progress.entries)
                    }
                    if !progress.unknown.isEmpty {
                        Section("Unknown Amount") { rows(progress.unknown) }
                    }
                    if !progress.otherUnits.isEmpty {
                        Section("Other Units") { rows(progress.otherUnits) }
                    }
                } else {
                    Text("This goal has been removed.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(goal.map { PersistenceController.shared.displayName(for: $0.substance) }
                             ?? String(localized: "Tracking Goal"))
            .toolbar {
                if let goal {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { draft = StatsGoalDraft(goal) } }
                }
            }
            .sheet(item: $draft) { draft in
                StatsGoalEditor(
                    draft: draft, entries: entries,
                    substances: goalSubstances(entries: entries, existing: goals), fixedSubstance: fixedSubstance
                ) { edited in
                    let updatedGoals = StatsPreferences.decodeGoals(data).map { $0.id == edited.id ? edited : $0 }
                    if let encoded = try? JSONEncoder().encode(updatedGoals) { data = encoded }
                }
            }
        }
    }

    private func rows(_ entries: [Ingestion]) -> some View {
        ForEach(entries) { entry in
            StatsIngestionLink(ingestion: entry, timeFormat: .dateTime.month().day().hour().minute())
        }
    }
}

private struct StatsGoalSummary: View {
    let goal: StatsGoal
    let progress: StatsGoal.Progress

    var body: some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))
        let value = progress.value.formatted(format)
        let target = goal.target.formatted(format)
        if goal.metric == .amount {
            Text("\(value) of \(target) \(goal.unit)")
        } else {
            Text("\(value) of \(target) ingestions")
        }
    }
}

private final class StatsGoalDraft: ObservableObject, Identifiable {
    @Published var goal: StatsGoal

    init(_ goal: StatsGoal) {
        self.goal = goal
    }
}

private struct StatsGoalEditor: View {
    @ObservedObject var draft: StatsGoalDraft
    let entries: [Ingestion]
    let substances: [String]
    let fixedSubstance: Bool
    let onSave: (StatsGoal) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if fixedSubstance {
                        LabeledContent("Substance", value: substanceLabel)
                    } else {
                        NavigationLink {
                            StatsGoalSubstancePicker(selection: $draft.goal.substance, journalNames: substances)
                        } label: {
                            LabeledContent("Substance", value: substanceLabel)
                        }
                    }
                    Picker("Measure", selection: $draft.goal.metric) {
                        ForEach(StatsGoal.Metric.allCases, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("Target", value: $draft.goal.target, format: .number)
                        .keyboardType(.decimalPad)
                    if goal.metric == .amount {
                        let existingUnits = Set(entries.filter {
                            $0.substanceNameUnwrapped == goal.substance && $0.customUnit == nil && !$0.unitsUnwrapped.isEmpty
                        }.map(\.unitsUnwrapped))
                        TextField("Unit as Logged", text: $draft.goal.unit)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !existingUnits.isEmpty {
                            Menu("Choose Recorded Unit") {
                                ForEach(existingUnits.sorted(), id: \.self) { unit in
                                    Button(unit) { draft.goal.unit = unit }
                                }
                            }
                        }
                    }
                    LabeledContent("Rolling Period") {
                        TextField("Days", value: $draft.goal.days, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Number of Days")
                        Text("days").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Goals use your confirmed logs. Recorded amounts count the exact unit you choose.")
                }
                Section {
                    Toggle("Show When Logging", isOn: $draft.goal.showsWhenLogging)
                }
            }
            .navigationTitle("Tracking Goal")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: goal.substance) { _ in draft.goal.unit = "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var edited = goal
                        edited.unit = edited.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(!goal.isValid || (goal.metric == .amount && goal.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }

    private var goal: StatsGoal { draft.goal }

    private var substanceLabel: String {
        goal.substance.isEmpty ? String(localized: "Choose Substance")
            : PersistenceController.shared.displayName(for: goal.substance)
    }
}

private struct StatsGoalSubstancePicker: View {
    @Binding var selection: String
    let journalNames: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>
    @State private var searchText = ""

    var body: some View {
        let names = options
        List {
            ForEach(names, id: \.self) { name in
                Button {
                    selection = name
                    dismiss()
                } label: {
                    HStack {
                        Text(PersistenceController.shared.displayName(for: name))
                        Spacer()
                        if selection == name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == name ? .isSelected : [])
            }
            if names.isEmpty {
                Text("No Substances Found").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Choose Substance")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Substances")
        .autocorrectionDisabled()
    }

    private var options: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = SubstanceRepo.shared.substances.filter { isEyeOpen || namesOfLegalSubstances.contains($0.name) }
        let references = SearchLogic.getFilteredSubstancesSorted(
            substances: catalog, searchText: query, namesToSortBy: journalNames
        ).map(\.name)
        let matchingLocalNames = (journalNames + customSubstances.map(\.nameUnwrapped))
            .filter { name in
                !name.isEmpty && (query.isEmpty || name.localizedStandardContains(query)
                    || PersistenceController.shared.displayName(for: name).localizedStandardContains(query))
            }
        return (matchingLocalNames + references).uniqued()
    }
}

struct StatsGoalLoggingSection: View {
    let substanceName: String
    let at: Date
    @AppStorage(StatsPreferences.goalsKey) private var data = Data()

    var body: some View {
        let goals = StatsPreferences.decodeGoals(data).filter { $0.substance == substanceName && $0.showsWhenLogging }
        if !goals.isEmpty {
            StatsJournal { entries, _ in
                Section {
                    ForEach(goals) { goal in
                        LabeledContent {
                            StatsGoalSummary(goal: goal, progress: goal.progress(in: entries, endingAt: at))
                        } label: {
                            Text("Last \(goal.days) Days")
                        }
                    }
                } header: {
                    Text("Tracking Goals")
                } footer: {
                    Text("Totals before this ingestion.")
                }
            }
        }
    }
}

// Observe the same context on every Stats screen. Updating an existing object can change every
// total while leaving the fetch count unchanged. This also handles changes merged from a save context.
struct StatsJournal<Content: View>: View {
    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    private var ingestions: FetchedResults<Ingestion>
    @Environment(\.managedObjectContext) private var context
    @State private var revision: UInt = 0

    @ViewBuilder let content: ([Ingestion], [String: PersonalSubstanceTags]) -> Content

    var body: some View {
        let _ = revision
        let entries = Array(ingestions)
        let substances = Set(entries.map(\.substanceNameUnwrapped))
        let tags = Dictionary(uniqueKeysWithValues: substances.map { substance in
            (substance, PersistenceController.shared.personalTags(for: substance))
        })

        content(entries, tags)
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { notification in
                if Self.affectsStats(notification) {
                    revision &+= 1
                }
            }
    }

    static func affectsStats(_ notification: Notification) -> Bool {
        guard let changes = notification.userInfo else { return false }
        if changes[NSInvalidatedAllObjectsKey] != nil { return true }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
        return keys.contains { key in
            let objects = changes[key] as? Set<NSManagedObject> ?? []
            return objects.contains { object in
                object is Ingestion || object is Experience || object is SubstanceCompanion || object is SubstanceOverride || object is CustomUnit
            }
        }
    }
}

extension Calendar {
    // swiftlint:disable identifier_name
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        return numberOfDays.day!
    }

    func numberOfMonthsBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfMonths = dateComponents([.month], from: fromDate, to: toDate)
        return numberOfMonths.month!
    }
    // swiftlint:enable identifier_name
}

#Preview {
    NavigationStack {
        StatsScreen()
            .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
    }
}
