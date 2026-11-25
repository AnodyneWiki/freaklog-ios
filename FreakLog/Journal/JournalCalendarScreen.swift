import CoreData
import SwiftUI
import HorizonCalendar
import UIKit

struct JournalCalendarScreen: View {

    @FetchRequest
    var ingestions: FetchedResults<Ingestion>

    @State private var isFirstAppear = true
    @State private var selectedDay: Date?
    @State private var pendingIngestionDeletion: IngestionDeletion.Request?
    @AppStorage(JournalDay.startHourKey) private var dayStartHour = 0
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var monthHeaderAllowance = 104.0

    private let substanceName: String?
    private let statsSelection: StatsSelection?

    init(substanceName: String? = nil, statsSelection: StatsSelection? = nil) {
        self.substanceName = substanceName
        self.statsSelection = statsSelection
        _ingestions = FetchRequest(fetchRequest: PersistenceController.historyIngestionsRequest(for: substanceName))
        self.monthsLayout = MonthsLayout.vertical

        let thirtyYears: TimeInterval = 30*12*30*24*60*60
        let startDate = Date.now.addingTimeInterval(-thirtyYears)
        let halfYear: TimeInterval = 6*30*24*60*60
        let endDate = Date.now.addingTimeInterval(halfYear)
        visibleDateRange = startDate...endDate
    }

    var body: some View {
        Group {
            if let statsSelection {
                StatsJournal { entries, tags in
                    let records = StatsRecords(
                        entries: entries, selection: statsSelection, calendar: calendar, dayStartHour: dayStartHour, tags: tags
                    )
                    calendarContent(entries: records.entries, scope: records.range)
                }
            } else {
                calendarContent(entries: Array(ingestions), scope: nil)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func calendarContent(entries: [Ingestion], scope: DateInterval?) -> some View {
        let ingestionsByDay = Dictionary(grouping: entries) { journalDay.label(for: $0.timeUnwrapped) }
        let range = historyDateRange(days: ingestionsByDay.keys, scope: scope)
        let today = journalDay.label(for: .now)
        let day = min(max(selectedDay ?? today, range.lowerBound), range.upperBound)
        return GeometryReader { geometry in
            let size = geometry.size
            let sideBySide = size.width >= 740
                || (size.width >= 610 && size.height < 430 && !dynamicTypeSize.isAccessibilitySize)
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            let calendarWidth = min(sideBySide ? size.width * 0.47 : size.width, 460)
            let dayMargin: CGFloat = calendarWidth < 345 ? 2 : 6
            let dayAspectRatio: CGFloat = dynamicTypeSize.isAccessibilitySize ? 1.3 : 1
            let dayWidth = max(0, calendarWidth - 6 * dayMargin) / 7
            let monthHeight = 6 * dayWidth * dayAspectRatio + 5 * 8 + monthHeaderAllowance

            layout {
                calendarPanel(
                    ingestionsByDay, range: range, activeDay: day, dayMargin: dayMargin, dayAspectRatio: dayAspectRatio
                )
                .frame(
                    width: calendarWidth,
                    height: sideBySide ? nil : min(monthHeight, size.height * 0.6)
                )
                Divider()
                dayEntries(ingestionsByDay[day] ?? [], on: day)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if range.contains(today) {
                    Button("Today") {
                        selectedDay = today
                        calendarViewProxy.scrollToDay(
                            containing: today,
                            scrollPosition: .centered,
                            animated: true)
                    }
                }
            }
        }
    }

    private func calendarPanel(
        _ ingestionsByDay: [Date: [Ingestion]],
        range: ClosedRange<Date>,
        activeDay: Date,
        dayMargin: CGFloat,
        dayAspectRatio: CGFloat
    ) -> some View {
        CalendarViewRepresentable(
            calendar: calendar,
            visibleDateRange: range,
            monthsLayout: monthsLayout,
            dataDependency: (ingestionsByDay, activeDay),
            proxy: calendarViewProxy
        )
        .interMonthSpacing(24)
        .verticalDayMargin(8)
        .horizontalDayMargin(dayMargin)
        .dayAspectRatio(dayAspectRatio)
        .monthHeaders { month in
            if let date = calendar.date(from: month.components) {
                Text(date, format: .dateTime.month(.wide).year())
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .days { dayComponents in
            if let date = calendar.date(from: dayComponents.components) {
                let day = calendar.startOfDay(for: date)
                DayView(date: day, ingestions: ingestionsByDay[day] ?? [], isSelected: day == activeDay) {
                    selectedDay = day
                }
            }
        }
        .task {
            guard isFirstAppear else { return }
            let initialDay = if substanceName != nil || statsSelection != nil {
                ingestionsByDay.keys.max() ?? range.upperBound
            } else {
                journalDay.label(for: .now)
            }
            selectedDay = min(max(initialDay, range.lowerBound), range.upperBound)
            await Task.yield()
            guard !Task.isCancelled, let selectedDay else { return }
            calendarViewProxy.scrollToDay(containing: selectedDay, scrollPosition: .centered, animated: false)
            isFirstAppear = false
        }
    }

    private func dayEntries(_ entries: [Ingestion], on day: Date) -> some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("No ingestions").foregroundStyle(.secondary)
                }
                ForEach(entries, id: \.objectID) { ingestion in
                    JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.hour().minute())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingIngestionDeletion = IngestionDeletion.Request(ingestion)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            } header: {
                Text(day, format: .dateTime.weekday(.wide).month().day().year())
            }
        }
        .listStyle(.insetGrouped)
        .confirmIngestionDeletion($pendingIngestionDeletion)
    }

    // MARK: Private

    private let monthsLayout: MonthsLayout
    private let visibleDateRange: ClosedRange<Date>

    @StateObject private var calendarViewProxy = CalendarViewProxy()

    private var journalDay: JournalDay { JournalDay(startHour: dayStartHour, calendar: calendar) }

    private func historyDateRange(days: Dictionary<Date, [Ingestion]>.Keys, scope: DateInterval?) -> ClosedRange<Date> {
        if let scope, scope.start != .distantPast, scope.end != .distantFuture {
            let first = journalDay.label(for: scope.start)
            let last = journalDay.lastLabel(in: scope)
            return min(first, days.min() ?? first)...max(last, days.max() ?? last)
        }
        guard substanceName != nil,
              let first = days.min(), let last = days.max()
        else { return calendar.startOfDay(for: visibleDateRange.lowerBound)...calendar.startOfDay(for: visibleDateRange.upperBound) }
        let today = journalDay.label(for: .now)
        return min(first, today)...max(last, today)
    }
}

extension PersistenceController {
    static func historyIngestionsRequest(for substanceName: String?) -> NSFetchRequest<Ingestion> {
        let request = ingestionsRequest()
        if let substanceName {
            request.predicate = NSPredicate(format: "substanceName == %@", substanceName)
        }
        return request
    }
}

struct SubstanceHistoryScreen: View {
    private let selection: StatsSelection

    init(substanceName: String, selection: StatsSelection = StatsSelection(period: .allTime, person: .everyone)) {
        self.selection = selection.forSubstance(substanceName)
    }

    var body: some View {
        StatsDetailScreen(metric: .ingestions, selection: selection, isSubstanceHistory: true)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct JournalEntryLink: View {
    @ObservedObject var ingestion: Ingestion
    let timeFormat: Date.FormatStyle

    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false

    var body: some View {
        if let experience = ingestion.experience {
            NavigationLink(value: GlobalNavigationDestination.experience(experience: experience)) {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        IngestionRow(ingestion: ingestion, isEyeOpen: isEyeOpen, isHidingDosageDots: isHidingDosageDots) {
            Text(ingestion.timeUnwrapped, format: timeFormat)
        }
    }
}

#Preview {
    NavigationStack {
        JournalCalendarScreen()
    }
}

