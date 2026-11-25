import CoreData
import SwiftUI
import HorizonCalendar
import UIKit

struct JournalCalendarScreen: View {

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    var ingestions: FetchedResults<Ingestion>

    @State private var isFirstAppear = true
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

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
            VStack(spacing: 0) {
                CalendarViewRepresentable(
                    calendar: calendar,
                    visibleDateRange: visibleDateRange,
                    monthsLayout: monthsLayout,
                    dataDependency: (ingestions, selectedDay),
                    proxy: calendarViewProxy)
                .interMonthSpacing(24)
                .verticalDayMargin(8)
                .horizontalDayMargin(8)
                .monthHeaders { month in
                    let monthHeaderText = monthDateFormatter.string(from: calendar.date(from: month.components)!)
                    HStack {
                        Text(monthHeaderText)
                            .font(.title2)
                        Spacer()
                    }
                    .padding()
                    .accessibilityAddTraits(.isHeader)
                }

                .days { dayComponents in
                    if let date = calendar.date(from: dayComponents.components) {
                        let day = calendar.startOfDay(for: date)
                        DayView(date: day, ingestions: ingestionsByDay[day] ?? [], isSelected: day == selectedDay) {
                            selectedDay = day
                        }
                    }
                }
                .frame(maxWidth: 375)
                .frame(height: geometry.size.height / 2)
                .task {
                    guard isFirstAppear else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    calendarViewProxy.scrollToDay(containing: selectedDay, scrollPosition: .centered, animated: false)
                    isFirstAppear = false
                }
                List {
                    Section {
                        let entries = ingestionsByDay[selectedDay] ?? []
                        if entries.isEmpty {
                            Text("No ingestions").foregroundStyle(.secondary)
                        }
                        ForEach(entries) { ingestion in
                            JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.hour().minute())
                        }
                    } header: {
                        Text(selectedDay, format: .dateTime.weekday(.wide).month().day().year())
                    }
                }
                .listStyle(.insetGrouped)
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

