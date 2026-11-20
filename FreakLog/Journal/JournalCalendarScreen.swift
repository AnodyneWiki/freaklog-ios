import SwiftUI
import HorizonCalendar
import UIKit

struct JournalCalendarScreen: View {

    @FetchRequest(fetchRequest: PersistenceController.ingestionsRequest())
    var ingestions: FetchedResults<Ingestion>

    @State private var isFirstAppear = true

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
        CalendarViewRepresentable(
            calendar: calendar,
            visibleDateRange: visibleDateRange,
            monthsLayout: monthsLayout,
            dataDependency: ingestions,
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
            DayView(dayComponents: dayComponents)
        }
        .onAppear {
            if isFirstAppear {
                calendarViewProxy.scrollToDay(
                    containing: Date.now,
                    scrollPosition: .lastFullyVisiblePosition(padding: 0),
                    animated: false)
                isFirstAppear = false
            }
        }
        .frame(maxWidth: 375, maxHeight: .infinity)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    calendarViewProxy.scrollToDay(
                        containing: Date.now,
                        scrollPosition: .lastFullyVisiblePosition(padding: 0),
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



#Preview {
    NavigationStack {
        JournalCalendarScreen()
    }
}

