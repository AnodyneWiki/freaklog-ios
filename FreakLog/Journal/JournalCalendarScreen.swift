import CoreData
import SwiftUI
import HorizonCalendar
import UIKit

struct JournalCalendarScreen: View {

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    var ingestions: FetchedResults<Ingestion>

    @State private var deletionRequest: IngestionDeletion.Request?
    @State private var isFirstAppear = true
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var monthHeaderAllowance = 104.0

    init() {
        self.calendar = Calendar.current
        self.monthsLayout = MonthsLayout.vertical

        let thirtyYears: TimeInterval = 30*12*30*24*60*60
        let startDate = Date.now.addingTimeInterval(-thirtyYears)
        let halfYear: TimeInterval = 6*30*24*60*60
        let endDate = Date.now.addingTimeInterval(halfYear)
        visibleDateRange = startDate...endDate

        monthDateFormatter = DateFormatter()
        monthDateFormatter.calendar = calendar
        monthDateFormatter.locale = calendar.locale
        monthDateFormatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "MMMM yyyy",
            options: 0,
            locale: calendar.locale ?? Locale.current)
    }

    var body: some View {
        // Grouped once here instead of a fetch request per visible day cell
        let ingestionsByDay = Dictionary(grouping: ingestions) { calendar.startOfDay(for: $0.timeUnwrapped) }
        GeometryReader { geometry in
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
                calendarPanel(ingestionsByDay, dayMargin: dayMargin, dayAspectRatio: dayAspectRatio)
                    .frame(
                        width: calendarWidth,
                        height: sideBySide ? nil : min(monthHeight, size.height * 0.6)
                    )
                Divider()
                dayEntries(ingestionsByDay[selectedDay] ?? [])
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    selectedDay = calendar.startOfDay(for: .now)
                    calendarViewProxy.scrollToDay(
                        containing: selectedDay,
                        scrollPosition: .centered,
                        animated: true)
                }
            }
        }
    }

    private func calendarPanel(
        _ ingestionsByDay: [Date: [Ingestion]],
        dayMargin: CGFloat,
        dayAspectRatio: CGFloat
    ) -> some View {
        CalendarViewRepresentable(
            calendar: calendar,
            visibleDateRange: visibleDateRange,
            monthsLayout: monthsLayout,
            dataDependency: (ingestions, selectedDay),
            proxy: calendarViewProxy
        )
        .interMonthSpacing(24)
        .verticalDayMargin(8)
        .horizontalDayMargin(dayMargin)
        .dayAspectRatio(dayAspectRatio)
        .monthHeaders { month in
            if let date = calendar.date(from: month.components) {
                Text(monthDateFormatter.string(from: date))
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .days { dayComponents in
            if let date = calendar.date(from: dayComponents.components) {
                let day = calendar.startOfDay(for: date)
                DayView(date: day, ingestions: ingestionsByDay[day] ?? [], isSelected: day == selectedDay) {
                    selectedDay = day
                }
            }
        }
        .task {
            guard isFirstAppear else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            calendarViewProxy.scrollToDay(containing: selectedDay, scrollPosition: .centered, animated: false)
            isFirstAppear = false
        }
    }

    private func dayEntries(_ entries: [Ingestion]) -> some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("No ingestions").foregroundStyle(.secondary)
                }
                ForEach(entries) { ingestion in
                    JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.hour().minute())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestIngestionDeletion(ingestion, confirmation: $deletionRequest)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(selectedDay, format: .dateTime.weekday(.wide).month().day().year())
            }
        }
        .listStyle(.insetGrouped)
        .confirmIngestionDeletion($deletionRequest)
    }

    // MARK: Private

    private let calendar: Calendar
    private let monthsLayout: MonthsLayout
    private let visibleDateRange: ClosedRange<Date>

    private let monthDateFormatter: DateFormatter

    @StateObject private var calendarViewProxy = CalendarViewProxy()
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

