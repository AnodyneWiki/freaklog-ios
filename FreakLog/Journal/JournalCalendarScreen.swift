import CoreData
import SwiftUI
import HorizonCalendar
import UIKit

struct JournalCalendarScreen: View {

    @FetchRequest
    var ingestions: FetchedResults<Ingestion>

    @State private var isFirstAppear = true
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private let substanceName: String?

    init(substanceName: String? = nil) {
        self.substanceName = substanceName
        _ingestions = FetchRequest(fetchRequest: PersistenceController.historyIngestionsRequest(for: substanceName))
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
                    visibleDateRange: historyDateRange,
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
                    if substanceName != nil, let latest = ingestions.first?.time {
                        selectedDay = calendar.startOfDay(for: latest)
                    }
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

    private var historyDateRange: ClosedRange<Date> {
        guard substanceName != nil,
              let first = ingestions.last?.time, let last = ingestions.first?.time
        else { return visibleDateRange }
        let start = calendar.startOfDay(for: min(first, .now))
        return start...max(last, Date.now)
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
    let substanceName: String
    @FetchRequest private var ingestions: FetchedResults<Ingestion>

    init(substanceName: String) {
        self.substanceName = substanceName
        _ingestions = FetchRequest(fetchRequest: PersistenceController.historyIngestionsRequest(for: substanceName))
    }

    var body: some View {
        List {
            if ingestions.isEmpty {
                Text("No journal entries yet").foregroundStyle(.secondary)
            } else {
                ForEach(ingestions) { ingestion in
                    JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.month().day().year().hour().minute())
                }
            }
        }
        .navigationTitle(PersistenceController.shared.displayName(for: substanceName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    JournalCalendarScreen(substanceName: substanceName)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
            }
        }
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

