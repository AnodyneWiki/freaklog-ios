import CoreData
import SwiftUI

struct JournalDay {
    static let startHourKey = "journalDayStartHour"

    let calendar: Calendar
    private let startHour: Int

    init(startHour: Int = 0, calendar: Calendar = .current) {
        self.calendar = calendar
        self.startHour = (0..<24).contains(startHour) ? startHour : 0
    }

    func start(of label: Date) -> Date {
        let midnight = calendar.startOfDay(for: label)
        guard startHour != 0 else { return midnight }
        let start = calendar.date(
            bySettingHour: startHour, minute: 0, second: 0, of: midnight,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first
        )
        return start.flatMap { calendar.isDate($0, inSameDayAs: midnight) ? $0 : nil } ?? midnight
    }

    func label(for time: Date) -> Date {
        let today = calendar.startOfDay(for: time)
        guard time < start(of: today) else { return today }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return calendar.startOfDay(for: yesterday)
    }

    func interval(of component: Calendar.Component, containing time: Date) -> DateInterval? {
        calendar.dateInterval(of: component, for: label(for: time)).map {
            DateInterval(start: start(of: $0.start), end: start(of: $0.end))
        }
    }

    func lastLabel(in interval: DateInterval) -> Date {
        label(for: max(interval.start, interval.end.addingTimeInterval(-0.001)))
    }

    // Swift Charts bins dates at civil boundaries. Keep its labels and tap targets on that same axis.
    func chartDomain(_ range: ClosedRange<Date>) -> ClosedRange<Date> {
        guard startHour != 0 else { return range }
        let interval = DateInterval(start: range.lowerBound, end: range.upperBound)
        let lastDay = lastLabel(in: interval)
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return label(for: range.lowerBound)...calendar.startOfDay(for: end)
    }
}

enum StatsPeriod: String, CaseIterable, Codable {
    case last7Days
    case last30Days
    case thisMonth
    case last12Months
    case allTime
    case custom

    var title: LocalizedStringKey {
        switch self {
        case .last7Days: "7 Days"
        case .last30Days: "30 Days"
        case .thisMonth: "Month"
        case .last12Months: "12 Months"
        case .allTime: "All Time"
        case .custom: "Custom Dates"
        }
    }
}

enum StatsMetric: String, Codable {
    case experiences
    case ingestions
    case amounts
    case gaps

    var title: LocalizedStringKey {
        switch self {
        case .experiences: "Experiences"
        case .ingestions: "Ingestions"
        case .amounts: "Recorded Amounts"
        case .gaps: "Time Between Logs"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "days" {
            self = .ingestions
        } else if let metric = Self(rawValue: rawValue) {
            self = metric
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized stats metric.")
        }
    }
}

struct StatsSelection: Codable, Equatable {
    enum Person: Codable, Equatable, Hashable {
        case me
        case everyone
        case named(String)
    }

    var period: StatsPeriod = .last30Days
    var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    var customEnd = Date.now
    var periodStep = 0
    var groupsByPrimaryTag = false
    var substances: Set<String> = []
    var route: AdministrationRoute?
    var person: Person = .me
    var tags: Set<String> = []
    var matchesPrimaryTagOnly = false
    var requiredPrimaryTag: String?
    var alongside: String?
    var alongsideFilter: EntryFilter?
    var focus: Focus?

    struct Focus: Codable, Equatable {
        let interval: DateInterval
        let metric: StatsMetric
        let sourceInterval: DateInterval
        let experienceFilter: EntryFilter?
        let experienceInterval: DateInterval?
    }

    struct EntryFilter: Codable, Equatable {
        let substances: Set<String>
        let route: AdministrationRoute?
        let person: Person
        let tags: Set<String>
        let matchesPrimaryTagOnly: Bool
        let requiredPrimaryTag: String?

        func includes(_ ingestion: Ingestion, tags personalTags: PersonalSubstanceTags) -> Bool {
            if !substances.isEmpty, !substances.contains(ingestion.substanceNameUnwrapped) { return false }
            if let route, route != StatsRecords.recordedRoute(for: ingestion) { return false }
            if let requiredPrimaryTag,
               personalTags.primary.map(PersonalSubstanceTags.key) != PersonalSubstanceTags.key(requiredPrimaryTag) { return false }
            if !tags.isEmpty {
                let names = matchesPrimaryTagOnly ? [personalTags.primary].compactMap { $0 } : personalTags.names
                let keys = Set(names.map(PersonalSubstanceTags.key))
                guard tags.contains(where: { keys.contains(PersonalSubstanceTags.key($0)) }) else { return false }
            }

            return includesPerson(ingestion)
        }

        func includesPerson(_ ingestion: Ingestion) -> Bool {
            switch person {
            case .me: return ingestion.isMine
            case .everyone: return true
            case .named(let name): return ingestion.consumerNameUnwrapped == name
            }
        }
    }

    init(
        period: StatsPeriod = .last30Days,
        customStart: Date = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
        customEnd: Date = .now,
        substance: String? = nil,
        route: AdministrationRoute? = nil,
        person: Person = .me,
        tag: String? = nil
    ) {
        self.period = period
        self.customStart = customStart
        self.customEnd = customEnd
        self.substances = substance.map { [$0] } ?? []
        self.route = route
        self.person = person
        self.tags = tag.map { [$0] } ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case period, customStart, customEnd, substances, route, person, tags, matchesPrimaryTagOnly, requiredPrimaryTag
        case alongside, alongsideFilter, focus, periodStep, groupsByPrimaryTag
    }

    private enum LegacyKeys: String, CodingKey {
        case substance, tag
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        self.init(
            period: try fields.decode(StatsPeriod.self, forKey: .period),
            customStart: try fields.decode(Date.self, forKey: .customStart),
            customEnd: try fields.decode(Date.self, forKey: .customEnd),
            substance: try legacy.decodeIfPresent(String.self, forKey: .substance),
            route: try fields.decodeIfPresent(AdministrationRoute.self, forKey: .route),
            person: try fields.decode(Person.self, forKey: .person),
            tag: try legacy.decodeIfPresent(String.self, forKey: .tag)
        )
        substances = try fields.decodeIfPresent(Set<String>.self, forKey: .substances) ?? substances
        tags = try fields.decodeIfPresent(Set<String>.self, forKey: .tags) ?? tags
        matchesPrimaryTagOnly = try fields.decodeIfPresent(Bool.self, forKey: .matchesPrimaryTagOnly) ?? false
        requiredPrimaryTag = try fields.decodeIfPresent(String.self, forKey: .requiredPrimaryTag)
        alongside = try fields.decodeIfPresent(String.self, forKey: .alongside)
        alongsideFilter = try fields.decodeIfPresent(EntryFilter.self, forKey: .alongsideFilter)
        focus = try fields.decodeIfPresent(Focus.self, forKey: .focus)
        periodStep = min(0, max(-1_000, try fields.decodeIfPresent(Int.self, forKey: .periodStep) ?? 0))
        groupsByPrimaryTag = try fields.decodeIfPresent(Bool.self, forKey: .groupsByPrimaryTag) ?? false
    }

    var singleSubstance: String? { substances.count == 1 ? substances.first : nil }

    func forSubstance(_ name: String) -> Self {
        var copy = self
        copy.substances = [name]
        return copy
    }

    func focused(on interval: DateInterval, metric: StatsMetric, within sourceInterval: DateInterval) -> Self {
        var copy = self
        let experienceFilter = focus?.experienceFilter ?? (metric == .experiences ? entryFilter : nil)
        let previousExperienceInterval = focus.flatMap { previous in
            previous.experienceFilter == nil ? nil : (previous.experienceInterval ?? previous.interval)
        }
        copy.focus = Focus(
            interval: interval, metric: metric, sourceInterval: sourceInterval,
            experienceFilter: experienceFilter, experienceInterval: previousExperienceInterval
        )
        return copy
    }

    var hasFilters: Bool {
        !substances.isEmpty || route != nil || !tags.isEmpty || requiredPrimaryTag != nil || person != .me
    }

    func dateRange(now: Date, calendar: Calendar = .current, dayStartHour: Int = 0) -> DateInterval {
        let journalDay = JournalDay(startHour: dayStartHour, calendar: calendar)
        let today = journalDay.label(for: now)
        let until = now.addingTimeInterval(0.001)
        switch period {
        case .last7Days, .last30Days:
            let days = period == .last7Days ? 7 : 30
            let start = calendar.date(byAdding: .day, value: days * periodStep - days + 1, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: days * periodStep + 1, to: today) ?? until
            return DateInterval(start: journalDay.start(of: start), end: min(journalDay.start(of: end), until))
        case .thisMonth:
            let date = calendar.date(byAdding: .month, value: periodStep, to: today) ?? today
            let month = calendar.dateInterval(of: .month, for: date)
            let start = journalDay.start(of: month?.start ?? today)
            let end = month.map { journalDay.start(of: $0.end) } ?? until
            return DateInterval(start: start, end: min(end, until))
        case .last12Months:
            let boundary = calendar.date(byAdding: .day, value: 1, to: today) ?? until
            let start = calendar.date(byAdding: .month, value: (periodStep - 1) * 12, to: boundary) ?? today
            let end = calendar.date(byAdding: .month, value: periodStep * 12, to: boundary) ?? until
            return DateInterval(start: journalDay.start(of: start), end: min(journalDay.start(of: end), until))
        case .allTime:
            return DateInterval(start: .distantPast, end: .distantFuture)
        case .custom:
            let firstDay = calendar.startOfDay(for: min(customStart, customEnd, today))
            let lastDay = calendar.startOfDay(for: min(max(customStart, customEnd), today))
            let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? until
            return DateInterval(start: journalDay.start(of: firstDay), end: min(journalDay.start(of: nextDay), until))
        }
    }

    func anchored(now: Date, calendar: Calendar = .current, dayStartHour: Int = 0) -> Self {
        guard periodStep < 0, period != .allTime, period != .custom else { return self }
        var copy = self
        let journalDay = JournalDay(startHour: dayStartHour, calendar: calendar)
        let interval = dateRange(now: now, calendar: calendar, dayStartHour: dayStartHour)
        copy.period = .custom
        copy.periodStep = 0
        copy.customStart = journalDay.label(for: interval.start)
        copy.customEnd = journalDay.lastLabel(in: interval)
        return copy
    }

    func includes(_ ingestion: Ingestion, tags: PersonalSubstanceTags) -> Bool {
        entryFilter.includes(ingestion, tags: tags)
    }

    var entryFilter: EntryFilter {
        EntryFilter(
            substances: substances, route: route, person: person, tags: tags,
            matchesPrimaryTagOnly: matchesPrimaryTagOnly, requiredPrimaryTag: requiredPrimaryTag
        )
    }
}

struct StatsRecords {
    private struct Cohort: Hashable {
        let experienceID: NSManagedObjectID
        let consumer: String?

        init?(_ entry: Ingestion) {
            guard let experience = entry.experience else { return nil }
            experienceID = experience.objectID
            consumer = Ingestion.storedConsumerName(entry.consumerNameUnwrapped)
        }
    }
    struct ExperienceMatch {
        let experience: Experience
        let firstMatchingDate: Date
        let entries: [Ingestion]
    }

    struct Bucket: Identifiable {
        var id: Date { interval.start }
        let interval: DateInterval
        let count: Int
    }

    struct Contribution: Identifiable {
        struct Key: Hashable {
            let date: Date
            let substance: String
        }

        let id: Key
        let count: Int
    }

    var ingestionContributions: [Contribution] {
        contributions(for: .ingestions)
    }

    func contributions(
        for metric: StatsMetric,
        group: ((Ingestion) -> String)? = nil,
        mixedGroup: String = ""
    ) -> [Contribution] {
        var counts: [Contribution.Key: Int] = [:]
        func count(at date: Date, in category: String) {
            guard let start = journalDay.interval(of: bucketComponent, containing: date)?.start else { return }
            counts[.init(date: start, substance: category), default: 0] += 1
        }
        switch metric {
        case .experiences:
            for match in experiences {
                let categories = Set(match.entries.compactMap { group?($0) })
                let category = categories.count == 1 ? categories.first ?? mixedGroup : mixedGroup
                count(at: match.firstMatchingDate, in: category)
            }
        case .ingestions:
            for entry in entries {
                guard let date = entry.time else { continue }
                count(at: date, in: group?(entry) ?? entry.substanceNameUnwrapped)
            }
        case .amounts, .gaps:
            break
        }
        return counts.map { Contribution(id: $0.key, count: $0.value) }.sorted {
            ($0.id.date, $0.id.substance) < ($1.id.date, $1.id.substance)
        }
    }

    struct Amount: Identifiable {
        struct Key: Hashable {
            let substance: String
            let unit: String
            let customUnitID: NSManagedObjectID?

            init(_ entry: Ingestion) {
                substance = entry.substanceNameUnwrapped
                customUnitID = entry.customUnit?.objectID
                let original = entry.unitsUnwrapped
                if customUnitID != nil {
                    unit = original
                } else if ["g", "mg", "µg", "μg", "mcg", "ug"].contains(original) {
                    unit = "mg"
                } else {
                    unit = original == "ml" ? "mL" : original
                }
            }

            func value(for entry: Ingestion) -> Double? {
                guard let recorded = StatsRecords.recordedAmount(entry) else { return nil }
                guard customUnitID == nil, unit == "mg" else { return recorded }
                let factor: Double
                switch entry.unitsUnwrapped {
                case "g": factor = 1_000
                case "µg", "μg", "mcg", "ug": factor = 0.001
                default: factor = 1
                }
                let result = recorded * factor
                return result.isFinite ? result : nil
            }

        }

        var id: Key { key }
        let key: Key
        let total: Double
        let count: Int
        let average: Double
        let median: Double
        let minimum: Double
        let maximum: Double
        let customUnitName: String?
        let experienceCount: Int
        let experienceAverage: Double?
    }

    struct AmountBucket: Identifiable {
        var id: Date { interval.start }
        let interval: DateInterval
        let total: Double
    }

    struct Gap: Identifiable {
        var id: NSManagedObjectID { newer.objectID }
        let older: Ingestion
        let newer: Ingestion
        let duration: TimeInterval
    }

    let range: DateInterval
    let entries: [Ingestion]
    let experiences: [ExperienceMatch]
    let journalDay: JournalDay

    init(
        entries: [Ingestion],
        selection: StatsSelection,
        now: Date = .now,
        calendar: Calendar = .current,
        dayStartHour: Int = 0,
        tags: [String: PersonalSubstanceTags] = [:]
    ) {
        let journalDay = JournalDay(startHour: dayStartHour, calendar: calendar)
        let range = selection.focus?.sourceInterval
            ?? selection.dateRange(now: now, calendar: calendar, dayStartHour: dayStartHour)
        let datedEntries = entries.filter { ingestion in
            guard !ingestion.isUnconfirmed, let time = ingestion.time else { return false }
            return range.start <= time && time < range.end
        }
        func matches(_ entry: Ingestion, filter: StatsSelection.EntryFilter) -> Bool {
            filter.includes(entry, tags: tags[entry.substanceNameUnwrapped, default: PersonalSubstanceTags()])
        }
        let filter = selection.entryFilter
        var alongsideCohorts: Set<Cohort>?
        if let anchor = selection.alongside {
            let anchors = datedEntries.filter { entry in
                guard entry.substanceNameUnwrapped == anchor else { return false }
                if let focus = selection.focus, focus.metric == .ingestions,
                   let time = entry.time, !(focus.interval.start <= time && time < focus.interval.end) {
                    return false
                }
                if let alongsideFilter = selection.alongsideFilter {
                    return matches(entry, filter: alongsideFilter)
                }
                return filter.includesPerson(entry)
            }
            alongsideCohorts = Set(anchors.compactMap(Cohort.init))
        }
        func scopedEntries(using filter: StatsSelection.EntryFilter) -> [Ingestion] {
            datedEntries.filter { entry in
                guard matches(entry, filter: filter) else { return false }
                if let alongsideCohorts {
                    return entry.substanceNameUnwrapped != selection.alongside && Cohort(entry).map(alongsideCohorts.contains) == true
                }
                return true
            }
        }
        let entries = scopedEntries(using: filter)
        if let focus = selection.focus, let firstFilter = focus.experienceFilter {
            let eligible = Self(entries: scopedEntries(using: firstFilter), range: range, journalDay: journalDay)
                .selecting(focus.experienceInterval ?? focus.interval, for: .experiences)
            let experienceIDs = Set(eligible.experiences.map(\.experience.objectID))
            let records = Self(
                entries: entries.filter { $0.experience.map { experienceIDs.contains($0.objectID) } == true },
                range: focus.experienceInterval == nil ? eligible.range : range,
                journalDay: journalDay
            )
            self = focus.experienceInterval == nil ? records : records.selecting(focus.interval, for: focus.metric)
        } else {
            let records = Self(entries: entries, range: range, journalDay: journalDay)
            self = selection.focus.map { records.selecting($0.interval, for: $0.metric) } ?? records
        }
    }

    private init(entries: [Ingestion], range: DateInterval, journalDay: JournalDay) {
        self.entries = entries
        self.range = range
        self.journalDay = journalDay
        var entriesByExperience: [NSManagedObjectID: [Ingestion]] = [:]
        for entry in entries {
            guard let experience = entry.experience else { continue }
            entriesByExperience[experience.objectID, default: []].append(entry)
        }
        experiences = entriesByExperience.values.compactMap { matches in
            guard let experience = matches.first?.experience,
                  let date = matches.compactMap(\.time).min() else { return nil }
            return ExperienceMatch(experience: experience, firstMatchingDate: date, entries: matches)
        }.sorted { $0.firstMatchingDate > $1.firstMatchingDate }
    }

    var daysLogged: Int {
        Set(entries.compactMap(\.time).map(journalDay.label)).count
    }

    static func recordedRoute(for entry: Ingestion) -> AdministrationRoute? {
        entry.administrationRoute.flatMap(AdministrationRoute.init(rawValue:))
    }

    var unknownAmountCount: Int { entries.filter { Amount.Key($0).value(for: $0) == nil }.count }

    var amounts: [Amount] {
        Self.amounts(in: entries)
    }

    static func amounts(in entries: [Ingestion]) -> [Amount] {
        let groups = Dictionary(grouping: entries, by: Amount.Key.init)
        return groups.compactMap { key, entries in
            let known = entries.compactMap(key.value).sorted()
            guard let minimum = known.first, let maximum = known.last else { return nil }
            let middle = known.count / 2
            let median = known.count.isMultiple(of: 2) ? known[middle - 1] / 2 + known[middle] / 2 : known[middle]
            let total = known.reduce(0, +)
            guard total.isFinite else { return nil }
            let linked = entries.filter { key.value(for: $0) != nil && $0.experience != nil }
            let experienceCount = Set(linked.compactMap { $0.experience?.objectID }).count
            let experienceAverage = experienceCount == 0 ? nil : linked.compactMap(key.value).reduce(0, +) / Double(experienceCount)
            return Amount(key: key, total: total, count: known.count, average: total / Double(known.count),
                          median: median, minimum: minimum, maximum: maximum,
                          customUnitName: entries.first?.customUnit?.nameUnwrapped,
                          experienceCount: experienceCount, experienceAverage: experienceAverage)
        }.sorted {
            ($0.key.substance, $0.key.unit, $0.customUnitName ?? "") < ($1.key.substance, $1.key.unit, $1.customUnitName ?? "")
        }
    }

    var amountTrends: [Amount.Key: [AmountBucket]] {
        let totals = entries.reduce(into: [Amount.Key: [DateInterval: Double]]()) { totals, entry in
            let key = Amount.Key(entry)
            guard let value = key.value(for: entry), let date = entry.time,
                  let interval = journalDay.interval(of: bucketComponent, containing: date) else { return }
            totals[key, default: [:]][interval, default: 0] += value
        }
        return totals.mapValues { buckets in
            buckets.filter { $0.value.isFinite }.map { AmountBucket(interval: $0.key, total: $0.value) }
                .sorted { $0.id < $1.id }
        }
    }

    var gapsBetweenLogs: [Gap] {
        guard Set(entries.map(\.substanceNameUnwrapped)).count == 1,
              Set(entries.map({ Ingestion.storedConsumerName($0.consumerNameUnwrapped) })).count == 1 else { return [] }
        let chronological = entries.sorted { $0.timeUnwrapped < $1.timeUnwrapped }
        return zip(chronological, chronological.dropFirst()).map { older, newer in
            Gap(older: older, newer: newer, duration: newer.timeUnwrapped.timeIntervalSince(older.timeUnwrapped))
        }.reversed()
    }

    var bucketComponent: Calendar.Component {
        if range.duration <= 35 * 86_400 { return .day }
        if range.duration <= 140 * 86_400 { return .weekOfYear }
        if range.duration <= 550 * 86_400 { return .month }
        return .year
    }

    func buckets(for metric: StatsMetric) -> [Bucket] {
        let dates: [Date]
        switch metric {
        case .experiences: dates = experiences.map(\.firstMatchingDate)
        case .ingestions, .amounts: dates = entries.compactMap(\.time)
        case .gaps: return []
        }

        let byInterval: [DateInterval: Int] = dates.reduce(into: [:]) { counts, date in
            if let interval = journalDay.interval(of: bucketComponent, containing: date) {
                counts[interval, default: 0] += 1
            }
        }
        return byInterval.map { Bucket(interval: $0.key, count: $0.value) }
            .sorted { $0.interval.start < $1.interval.start }
    }

    func chartDomain(covering buckets: [Bucket]) -> ClosedRange<Date>? {
        chartDomain(covering: buckets.map(\.interval))
    }

    func chartDomain(covering intervals: [DateInterval]) -> ClosedRange<Date>? {
        guard let first = intervals.first, let last = intervals.last else { return nil }
        let start = range.start == .distantPast ? first.start : min(first.start, range.start)
        let end = range.end == .distantFuture ? last.end : max(last.end, range.end)
        return journalDay.chartDomain(start...end)
    }

    func selecting(_ bucket: Bucket, for metric: StatsMetric) -> Self {
        selecting(bucket.interval, for: metric)
    }

    func selecting(_ selectedInterval: DateInterval, for metric: StatsMetric) -> Self {
        // An experience bucket can carry follow-up ingestions beyond its first matching date.
        let dates = entries.compactMap(\.time)
        let start = min(range.start, dates.min() ?? range.start)
        let end = max(range.end, dates.max()?.addingTimeInterval(0.001) ?? range.end)
        guard let interval = DateInterval(start: start, end: end).intersection(with: selectedInterval) else {
            return Self(entries: [], range: selectedInterval, journalDay: journalDay)
        }
        if metric == .experiences {
            let matches = experiences.filter { interval.start <= $0.firstMatchingDate && $0.firstMatchingDate < interval.end }
            return Self(entries: matches.flatMap(\.entries), range: interval, journalDay: journalDay)
        }
        return Self(entries: entries.filter { entry in
            guard let date = entry.time else { return false }
            return interval.start <= date && date < interval.end
        }, range: interval, journalDay: journalDay)
    }

    private static func recordedAmount(_ ingestion: Ingestion) -> Double? {
        guard let amount = ingestion.doseUnwrapped, amount.isFinite else { return nil }
        return amount
    }
}

struct StatsPeriodControls: View {
    @Binding var period: StatsPeriod
    @Binding var start: Date
    @Binding var end: Date
    @Binding var step: Int
    @AppStorage(JournalDay.startHourKey) private var dayStartHour = 0

    var body: some View {
        Picker("Period", selection: Binding(
            get: { period },
            set: { period = $0; step = 0 }
        )) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        }
        if period == .custom {
            let today = JournalDay(startHour: dayStartHour).label(for: .now)
            DatePicker("From", selection: Binding(
                get: { min(start, today) },
                set: { date in
                    start = date
                    if Calendar.current.compare(date, to: end, toGranularity: .day) == .orderedDescending {
                        end = date
                    }
                }
            ), in: ...today, displayedComponents: .date)
            DatePicker("Through", selection: Binding(
                get: { min(end, today) },
                set: { date in
                    end = date
                    if Calendar.current.compare(date, to: start, toGranularity: .day) == .orderedAscending {
                        start = date
                    }
                }
            ), in: ...today, displayedComponents: .date)
        } else if period != .allTime {
            let now = Date.now
            var selection: StatsSelection {
                var selection = StatsSelection(period: period)
                selection.periodStep = step
                return selection
            }
            HStack {
                Button {
                    step -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Previous Period")
                .disabled(step <= -1_000)

                Text(statsRangeLabel(
                    selection.dateRange(now: now, dayStartHour: dayStartHour), journalDay: .init(startHour: dayStartHour)
                ))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button {
                    step += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Next Period")
                .disabled(step == 0)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct StatsCoverageRows: View {
    let records: StatsRecords

    var body: some View {
        LabeledContent("Experiences", value: records.experiences.count.formatted())
        LabeledContent("Days Logged", value: records.daysLogged.formatted())
    }
}

struct PinnedStatsView: Codable, Identifiable {
    var id = UUID()
    let name: String
    let metric: StatsMetric
    let selection: StatsSelection
}

struct StatsGoal: Codable, Identifiable {
    enum Metric: String, Codable, CaseIterable {
        case count, amount

        var title: LocalizedStringKey { self == .count ? "Ingestion Count" : "Recorded Amount" }
    }

    var id = UUID()
    var substance: String
    var days = 30
    var metric: Metric = .count
    var target = 0.0
    var unit = ""
    var showsWhenLogging = false

    var isValid: Bool {
        guard !substance.isEmpty, (1...365).contains(days), target.isFinite, target > 0 else { return false }
        switch metric {
        case .count: return target.rounded() == target
        case .amount: return !unit.isEmpty
        }
    }

    func progress(
        in entries: [Ingestion], endingAt end: Date, calendar: Calendar = .current, dayStartHour: Int = 0
    ) -> Progress {
        let journalDay = JournalDay(startHour: dayStartHour, calendar: calendar)
        let label = calendar.date(byAdding: .day, value: 1 - days, to: journalDay.label(for: end)) ?? end
        let start = journalDay.start(of: label)
        let entries = entries.filter { entry in
            guard entry.substanceNameUnwrapped == substance, entry.isMine, !entry.isUnconfirmed,
                  let time = entry.time else { return false }
            return start <= time && time <= end
        }
        if metric == .count {
            return Progress(value: Double(entries.count), entries: entries, unknown: [], otherUnits: [])
        }

        let unknown = entries.filter { Self.validAmount($0) == nil }
        let known = entries.filter { Self.validAmount($0) != nil }
        let matching = known.filter { $0.customUnit == nil && $0.unitsUnwrapped == unit }
        let otherUnits = known.filter { $0.customUnit != nil || $0.unitsUnwrapped != unit }
        let value = matching.compactMap(Self.validAmount).reduce(0, +)
        return Progress(value: min(value, Double.greatestFiniteMagnitude), entries: matching, unknown: unknown, otherUnits: otherUnits)
    }

    private static func validAmount(_ entry: Ingestion) -> Double? {
        guard let amount = entry.doseUnwrapped, amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    struct Progress {
        let value: Double
        let entries: [Ingestion]
        let unknown: [Ingestion]
        let otherUnits: [Ingestion]
    }
}
