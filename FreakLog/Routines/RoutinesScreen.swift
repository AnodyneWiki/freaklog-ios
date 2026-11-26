import CoreData
import SwiftUI
import UIKit

struct RoutinesScreen: View {
    var body: some View {
        RoutineDayScreen(mode: .agenda)
    }
}

private struct RoutineManagementScreen: View {
    @ObservedObject private var store = RoutineSchedules.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: RoutineSchedule?
    @State private var copiedProductID: NSManagedObjectID?
    @State private var testReminderError: String?
    @AppStorage(PersistenceController.showsDueTodayKey) private var showsDueToday = false
    @FetchRequest(sortDescriptors: []) private var records: FetchedResults<RoutineRecord>

    var body: some View {
        List {
            if let loadError = store.loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.circle")
                    Button("Try Again") { Task { await store.refresh() } }
                        .disabled(store.isUpdating)
                }
            } else {
                Section {
                    if store.schedules.isEmpty, !store.isUpdating {
                        Text("No routines yet").foregroundStyle(.secondary)
                    }
                    ForEach(store.schedules) { schedule in
                        Button {
                            copiedProductID = nil
                            selection = schedule
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(schedule.name).foregroundStyle(.primary)
                                Text(schedule.summary(unit: records.first(where: { $0.id == schedule.id })?.productUnit))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edits the routine")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                let record = try? RoutineSchedules.record(
                                    for: schedule.id, in: PersistenceController.shared.viewContext
                                )
                                copiedProductID = record?.customUnit?.objectID ?? record?.formulation?.objectID
                                selection = schedule.duplicate(calendar: RoutineSchedules.calendar)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.accentColor)
                        }
                    }
                }

                Section {
                    Toggle("Show Due Today in Journal", isOn: $showsDueToday)
                    Button("Send Test Reminder") {
                        Task {
                            do {
                                try await store.sendTestReminder()
                            } catch {
                                testReminderError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(store.isUpdating || store.authorization == .denied)
                } footer: {
                    Text("Reminders use a generic message. A test reminder arrives in a few seconds.")
                }

                if store.authorization == .denied {
                    Section {
                        Text("Notifications are turned off for FreakLog.")
                        Button("Open Notification Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                } else if store.authorization == .notDetermined, store.schedules.contains(where: \.reminds) {
                    Section {
                        Button("Allow Notifications") { Task { await store.refresh(askingPermission: true) } }
                            .disabled(store.isUpdating)
                    }
                }

                if let reminderError = store.reminderError {
                    Section {
                        Label(reminderError, systemImage: "exclamationmark.circle")
                        Button("Retry Reminders") { Task { await store.refresh() } }
                            .disabled(store.isUpdating)
                    }
                }
            }
        }
        .navigationTitle("Manage Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copiedProductID = nil
                    selection = .draft(calendar: RoutineSchedules.calendar)
                } label: {
                    Label("Add Routine", systemImage: "plus")
                }
                .disabled(store.isUpdating || store.loadError != nil)
            }
        }
        .sheet(item: $selection) { schedule in
            RoutineScheduleEditor(
                schedule: schedule,
                isNew: !store.schedules.contains(where: { $0.id == schedule.id }),
                store: store, initialProductID: copiedProductID
            )
        }
        .task { await store.refresh() }
        .alert("Couldn’t Send Test Reminder", isPresented: Binding(
            get: { testReminderError != nil },
            set: { if !$0 { testReminderError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testReminderError ?? "")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

extension RoutineSchedule {
    @MainActor func summary(unit: String?) -> String {
        let calendar = RoutineSchedules.calendar
        let times = times.sorted { $0.minuteOfDay < $1.minuteOfDay }
        let formattedTime = times.compactMap { time -> String? in
            guard let date = time.date(in: calendar) else { return nil }
            let label = date.formatted(date: .omitted, time: .shortened)
            guard let unit else { return label }
            guard let amount = time.productAmount ?? productAmount else {
                return String(localized: "\(label) (amount at logging)")
            }
            return String(localized: "\(label) (\(amount.formatted(routineAmountFormat)) \(unit))")
        }
            .formatted(.list(type: .and))
        var parts = [String]()
        if isAsNeeded {
            parts.append(String(localized: "As needed"))
        } else if let day = monthlyDay {
            parts.append(String(localized: "Monthly on day \(day) at \(formattedTime)"))
        } else if let interval = intervalDays {
            parts.append(String(localized: "Every \(interval) days at \(formattedTime)"))
            if let weekdays {
                let symbols = calendar.shortWeekdaySymbols
                let days = calendar.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }
                parts.append(days.formatted(.list(type: .and)))
            }
        } else if let weekdays {
            let symbols = calendar.shortWeekdaySymbols
            let days = calendar.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }
            parts.append(String(localized: "\(days.formatted(.list(type: .and))) at \(formattedTime)"))
        } else {
            parts.append(String(localized: "Every day at \(formattedTime)"))
        }
        if isPaused { parts.append(String(localized: "Paused")) }
        if let end = endDay?.date(in: calendar) {
            parts.append(String(localized: "Through \(end.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

private let routineAmountFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...8))

extension JournalPresetProduct {
    @MainActor var routineUnit: String {
        switch self {
        case .customUnit(let unit): unit.unitUnwrapped
        case .formulation: Inventory.Use.formulationUnit
        }
    }
}

private extension RoutineRecord {
    @MainActor var productUnit: String? {
        if let customUnit { return JournalPresetProduct.customUnit(customUnit).routineUnit }
        if let formulation { return JournalPresetProduct.formulation(formulation).routineUnit }
        return nil
    }
}

struct RoutineScheduleEditor: View {
    private enum Frequency: Hashable {
        case daily, selectedDays, interval, monthly, asNeeded
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RoutineSchedules
    @State private var schedule: RoutineSchedule
    @State private var time: Date
    @State private var productID: NSManagedObjectID?
    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest(filter: ""))
    private var customUnits: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>
    @State private var showsDeleteConfirmation = false
    @State private var error: String?
    let isNew: Bool
    let showsProductLink: Bool

    init(
        schedule: RoutineSchedule, isNew: Bool, store: RoutineSchedules, initialProductID: NSManagedObjectID? = nil,
        showsProductLink: Bool = true
    ) {
        _schedule = State(initialValue: schedule)
        _productID = State(initialValue: initialProductID)
        _time = State(initialValue: Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: schedule.hour, minute: schedule.minute),
            matchingPolicy: .strict
        ) ?? .now)
        self.isNew = isNew
        self.store = store
        self.showsProductLink = showsProductLink
    }

    var body: some View {
        NavigationStack {
            Form {
                let updated = preparedSchedule
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                    }
                }

                Section {
                    TextField("Routine Name", text: $schedule.name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Saved Product") {
                    NavigationLink {
                        SavedProductPicker(selection: changingProduct, emptyTitle: "Choose When Logging")
                    } label: {
                        if let selectedProduct {
                            SavedProductRow(product: selectedProduct)
                        } else {
                            LabeledContent("Product", value: "Choose When Logging")
                        }
                    }
                    if let product = selectedProduct {
                        if showsProductLink {
                            NavigationLink {
                                ProductDetailScreen(product: product)
                            } label: {
                                Label("View Product", systemImage: "shippingbox")
                            }
                        }
                    } else if schedule.productKind != nil {
                        Text("The saved product is unavailable. Choose another product or choose when logging.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Schedule") {
                    Picker("Repeat", selection: frequency) {
                        Text("Every Day").tag(Frequency.daily)
                        Text("Selected Days").tag(Frequency.selectedDays)
                        Text("Fixed Interval").tag(Frequency.interval)
                        Text("Monthly").tag(Frequency.monthly)
                        Text("As Needed").tag(Frequency.asNeeded)
                    }
                    if schedule.weekdays != nil {
                        ForEach(Calendar.current.orderedWeekdays, id: \.self) { weekday in
                            Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: selection(for: weekday))
                        }
                    }
                    if schedule.intervalDays != nil {
                        Stepper(
                            value: Binding(get: { schedule.intervalDays ?? 2 }, set: { schedule.intervalDays = $0 }),
                            in: 2...365
                        ) {
                            Text("Every \(schedule.intervalDays ?? 2) days")
                        }
                        Toggle("Limit to Selected Days", isOn: limitsIntervalToWeekdays)
                        Text("Days outside this selection are skipped. The interval still starts on the first day.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if schedule.monthlyDay != nil {
                        Picker("Day of Month", selection: monthlyDay) {
                            ForEach(1...31, id: \.self) { day in Text(day.formatted()).tag(day) }
                        }
                        Text("In shorter months, use the last day.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DatePicker("First Day", selection: firstDay, displayedComponents: .date)
                    Toggle("Ends on a Date", isOn: hasEndDay)
                    if schedule.endDay != nil {
                        DatePicker("Last Day", selection: lastDay, in: firstDay.wrappedValue..., displayedComponents: .date)
                    }
                }

                if !schedule.isAsNeeded {
                    Section("Times") {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        if let unit = selectedProduct?.routineUnit { defaultAmount(unit: unit) }
                        ForEach(schedule.additionalTimes ?? []) { entry in additionalTimeRow(entry) }
                        Button(action: addTime) {
                            Label("Add Time", systemImage: "plus.circle")
                        }
                    }
                } else if let unit = selectedProduct?.routineUnit {
                    Section("Logging") { defaultAmount(unit: unit) }
                }

                if let message = validationMessage(for: updated) {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    }
                } else if !updated.isAsNeeded && !updated.isPaused {
                    Section("Next Occurrences") {
                        let upcoming = updated.nextSlots(after: .now, calendar: RoutineSchedules.calendar, limit: 3)
                        if upcoming.isEmpty {
                            Text("No upcoming occurrences").foregroundStyle(.secondary)
                        }
                        ForEach(upcoming) { slot in
                            LabeledContent {
                                if let amount = updated.amount(for: slot), let unit = selectedProduct?.routineUnit {
                                    Text("\(amount.formatted(routineAmountFormat)) \(unit)")
                                }
                            } label: {
                                Text(slot.scheduledAt, format: .dateTime.weekday().month().day().hour().minute())
                            }
                        }
                    }
                }

                Section {
                    Toggle("Paused", isOn: Binding(
                        get: { schedule.isPaused }, set: { schedule.setPaused($0) }
                    ))
                    if !schedule.isAsNeeded { Toggle("Remind Me", isOn: $schedule.reminds) }
                } footer: {
                    if schedule.isAsNeeded {
                        Text("Log this routine whenever you need it from the Routines screen.")
                    } else {
                        Text("Reminders omit the routine name.")
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Routine", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } footer: {
                        Text("Schedule edits apply today. Earlier schedule dates are kept.")
                    }
                }
            }
            .disabled(store.isUpdating)
            .navigationTitle(isNew ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isUpdating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(store.isUpdating || validationMessage(for: preparedSchedule) != nil)
                }
            }
            .confirmationDialog("Delete this routine?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive, action: delete)
            } message: {
                Text("This removes the routine and its schedule history. Journal entries stay in your journal.")
            }
        }
        .interactiveDismissDisabled(store.isUpdating)
        .onFirstAppear {
            guard !isNew,
                  let record = try? RoutineSchedules.record(for: schedule.id, in: PersistenceController.shared.viewContext)
            else { return }
            productID = record.customUnit?.objectID ?? record.formulation?.objectID
        }
    }

    private var selectedProduct: JournalPresetProduct? {
        if let unit = customUnits.first(where: { $0.objectID == productID }) { return .customUnit(unit) }
        return formulations.first(where: { $0.objectID == productID }).map(JournalPresetProduct.formulation)
    }

    private var changingProduct: Binding<NSManagedObjectID?> {
        Binding(
            get: { productID },
            set: { newProduct in
                guard productID != newProduct else { return }
                productID = newProduct
                schedule.productAmount = nil
                if let times = schedule.additionalTimes {
                    schedule.additionalTimes = times.map { time in
                        var changed = time
                        changed.productAmount = nil
                        return changed
                    }
                }
            }
        )
    }

    private var frequency: Binding<Frequency> {
        Binding(
            get: {
                if schedule.intervalDays != nil { return .interval }
                if schedule.monthlyDay != nil { return .monthly }
                if schedule.isAsNeeded { return .asNeeded }
                return schedule.weekdays == nil ? .daily : .selectedDays
            },
            set: { value in
                let calendar = RoutineSchedules.calendar
                if schedule.anchorDay == nil { schedule.anchorDay = .init(.now, calendar: calendar) }
                schedule.weekdays = value == .selectedDays ? [calendar.component(.weekday, from: .now)] : nil
                schedule.intervalDays = value == .interval ? 2 : nil
                schedule.monthlyDay = value == .monthly ? calendar.component(.day, from: firstDay.wrappedValue) : nil
                schedule.asNeeded = value == .asNeeded ? true : nil
                if value == .asNeeded { schedule.reminds = false }
            }
        )
    }

    private var monthlyDay: Binding<Int> {
        Binding(get: { schedule.monthlyDay ?? 1 }, set: { schedule.monthlyDay = $0 })
    }

    private var limitsIntervalToWeekdays: Binding<Bool> {
        Binding(
            get: { schedule.weekdays != nil },
            set: { enabled in
                let weekday = RoutineSchedules.calendar.component(.weekday, from: firstDay.wrappedValue)
                schedule.weekdays = enabled ? [weekday] : nil
            }
        )
    }

    private func defaultAmount(unit: String) -> some View {
        LabeledContent("Default Amount") {
            TextField("Choose When Logging", value: $schedule.productAmount, format: routineAmountFormat)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .accessibilityLabel("Default Amount")
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func validationMessage(for updated: RoutineSchedule) -> String? {
        if updated.name.isEmpty { return String(localized: "Enter a name for this routine.") }
        if productID != nil && selectedProduct == nil { return String(localized: "Choose an available saved product.") }
        if updated.weekdays?.isEmpty == true { return String(localized: "Select at least one day.") }
        if !updated.intervalCanReachSelectedDays(calendar: RoutineSchedules.calendar) {
            return String(localized: "Include the weekday of the first day, or choose a different interval.")
        }
        if Set(updated.times.map(\.minuteOfDay)).count != updated.times.count {
            return String(localized: "Choose a different time for each occurrence.")
        }
        if !updated.isValid { return String(localized: "Enter an amount greater than zero or leave the amount blank.") }
        return nil
    }

    private var firstDay: Binding<Date> {
        Binding(
            get: { schedule.anchorDay?.date(in: RoutineSchedules.calendar) ?? RoutineSchedules.calendar.startOfDay(for: .now) },
            set: {
                let calendar = RoutineSchedules.calendar
                schedule.anchorDay = .init($0, calendar: calendar)
                if let end = schedule.endDay?.date(in: calendar), end < calendar.startOfDay(for: $0) {
                    schedule.endDay = schedule.anchorDay
                }
            }
        )
    }

    private var hasEndDay: Binding<Bool> {
        Binding(
            get: { schedule.endDay != nil },
            set: { schedule.endDay = $0 ? .init(max(firstDay.wrappedValue, .now), calendar: RoutineSchedules.calendar) : nil }
        )
    }

    private var lastDay: Binding<Date> {
        Binding(
            get: { schedule.endDay?.date(in: RoutineSchedules.calendar) ?? firstDay.wrappedValue },
            set: { schedule.endDay = .init($0, calendar: RoutineSchedules.calendar) }
        )
    }

    private func selection(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { schedule.weekdays?.contains(weekday) == true },
            set: { isSelected in
                if isSelected {
                    schedule.weekdays?.insert(weekday)
                } else {
                    schedule.weekdays?.remove(weekday)
                }
            }
        )
    }

    private func timeBinding(for entry: RoutineSchedule.ClockTime) -> Binding<Date> {
        Binding(
            get: {
                let current = schedule.additionalTimes?.first(where: { $0.id == entry.id }) ?? entry
                return current.date(in: RoutineSchedules.calendar) ?? .now
            },
            set: { date in
                guard let index = schedule.additionalTimes?.firstIndex(where: { $0.id == entry.id }) else { return }
                let calendar = RoutineSchedules.calendar
                schedule.additionalTimes?[index].hour = calendar.component(.hour, from: date)
                schedule.additionalTimes?[index].minute = calendar.component(.minute, from: date)
            }
        )
    }

    private func amountBinding(for entry: RoutineSchedule.ClockTime) -> Binding<Double?> {
        Binding(
            get: { schedule.additionalTimes?.first(where: { $0.id == entry.id })?.productAmount },
            set: { amount in
                guard let index = schedule.additionalTimes?.firstIndex(where: { $0.id == entry.id }) else { return }
                schedule.additionalTimes?[index].productAmount = amount
            }
        )
    }

    private func additionalTimeRow(_ entry: RoutineSchedule.ClockTime) -> some View {
        VStack(spacing: 8) {
            HStack {
                DatePicker("Time", selection: timeBinding(for: entry), displayedComponents: .hourAndMinute)
                Button(role: .destructive) {
                    schedule.additionalTimes?.removeAll { $0.id == entry.id }
                } label: {
                    Label("Remove Time", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Remove \(timeBinding(for: entry).wrappedValue.formatted(date: .omitted, time: .shortened))"))
                .buttonStyle(.borderless)
            }
            if let unit = selectedProduct?.routineUnit {
                let defaultAmount = schedule.productAmount.map {
                    String(localized: "Default (\($0.formatted(routineAmountFormat)))")
                } ?? String(localized: "Choose When Logging")
                LabeledContent("Amount") {
                    TextField(defaultAmount, value: amountBinding(for: entry), format: routineAmountFormat)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(Text("Amount at \(timeBinding(for: entry).wrappedValue.formatted(date: .omitted, time: .shortened))"))
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addTime() {
        let updated = preparedSchedule
        let used = Set(updated.times.map(\.minuteOfDay))
        let first = updated.hour * 60 + updated.minute
        guard let next = (1..<1_440).lazy.map({ (first + 60 + $0 - 1) % 1_440 }).first(where: { !used.contains($0) })
        else { return }
        var additional = schedule.additionalTimes ?? []
        additional.append(.init(hour: next / 60, minute: next % 60))
        schedule.additionalTimes = additional
    }

    private var preparedSchedule: RoutineSchedule {
        var updated = schedule
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = RoutineSchedules.calendar.dateComponents([.hour, .minute], from: time)
        updated.hour = components.hour ?? schedule.hour
        updated.minute = components.minute ?? schedule.minute
        updated.productKind = productID.map { id in
            customUnits.contains(where: { $0.objectID == id }) ? .customUnit : .formulation
        }
        updated.productAmount = productID == nil ? nil : schedule.productAmount
        if updated.isAsNeeded { updated.additionalTimes = nil }
        return updated
    }

    private func save() {
        error = nil
        let updated = preparedSchedule
        let productID = productID
        Task {
            do {
                try await store.save(updated, productID: productID)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete() {
        error = nil
        Task {
            do {
                try await store.delete(schedule.id)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct RoutineDayScreen: View {
    enum Mode { case agenda, day, history }

    var mode = Mode.day
    @ObservedObject private var store = RoutineSchedules.shared
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "scheduledAt", ascending: true)])
    private var occurrences: FetchedResults<RoutineOccurrence>
    @FetchRequest(sortDescriptors: []) private var records: FetchedResults<RoutineRecord>
    @State private var selectedDay = Date()
    @State private var logging: RoutineOccurrenceSlot?
    @State private var newRoutine: RoutineSchedule?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            dayList(at: tick.date)
        }
        .navigationTitle(title)
        .task { await store.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .toolbar {
            if mode == .agenda {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        RoutineManagementScreen()
                    } label: {
                        Label("Manage Routines", systemImage: "list.bullet")
                    }
                    Button {
                        newRoutine = .draft(calendar: RoutineSchedules.calendar)
                    } label: {
                        Label("Add Routine", systemImage: "plus")
                    }
                    .disabled(store.isUpdating || store.loadError != nil)
                }
            }
        }
        .sheet(item: $newRoutine) { schedule in
            RoutineScheduleEditor(schedule: schedule, isNew: true, store: store)
        }
        .sheet(item: $logging, onDismiss: { Task { await store.refresh() } }) { slot in
            RoutineLogSheet(
                record: records.first(where: { $0.id == slot.scheduleID }),
                slot: slot,
                dismiss: { logging = nil }
            )
            .environment(\.routineOccurrenceSlot, slot)
            .environment(\.addIngestionStartTime,
                          RoutineSchedules.calendar.isDateInToday(slot.scheduledAt) ? nil : slot.scheduledAt)
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .agenda: "Routines"
        case .day where RoutineSchedules.calendar.isDateInToday(selectedDay): "Due Today"
        case .day, .history: "Routine History"
        }
    }

    private func dayList(at now: Date) -> some View {
        let calendar = RoutineSchedules.calendar
        let day = mode == .agenda ? now : selectedDay
        let occurrencesByKey = Dictionary(grouping: occurrences) { $0.key ?? "" }
        let rows = slots(for: day, calendar: calendar)
        return List {
            if mode != .agenda {
                DatePicker("Date", selection: $selectedDay, in: ...now, displayedComponents: .date)
            }
            if let error = error ?? store.loadError ?? store.reminderError {
                Label(error, systemImage: "exclamationmark.circle")
            }
            if mode == .agenda {
                agendaSections(rows: rows, at: now, calendar: calendar, occurrencesByKey: occurrencesByKey)
                Section {
                    NavigationLink {
                        RoutineDayScreen(mode: .history)
                    } label: {
                        Label("Routine History", systemImage: "calendar")
                    }
                }
            } else {
                if rows.isEmpty {
                    Text("No routines for this day").foregroundStyle(.secondary)
                }
                slotRows(rows, occurrencesByKey: occurrencesByKey, now: now)
            }
        }
    }

    @ViewBuilder
    private func agendaSections(
        rows: [RoutineOccurrenceSlot], at now: Date, calendar: Calendar,
        occurrencesByKey: [String: [RoutineOccurrence]]
    ) -> some View {
        let completed = rows.filter { slot in
            occurrencesByKey[slot.id]?.contains { $0.isSkipped || ($0.ingestions?.count ?? 0) > 0 } == true
        }
        let completedIDs = Set(completed.map(\.id))
        let pending = rows.filter { !completedIDs.contains($0.id) }
        let overdue = pending.filter { slot in
            let due = occurrencesByKey[slot.id]?.compactMap(\.snoozedUntil).max() ?? slot.scheduledAt
            return due < now
        }
        let overdueIDs = Set(overdue.map(\.id))
        let laterToday = pending.filter { !overdueIDs.contains($0.id) }
        let asNeeded = store.schedules.filter { $0.canLogAsNeeded(at: now, calendar: calendar) }
        let upcoming = nextRoutines(at: now, calendar: calendar, occurrencesByKey: occurrencesByKey)

        if pending.isEmpty && completed.isEmpty {
            Section("Today") {
                Text("No scheduled routines today").foregroundStyle(.secondary)
            }
        }
        if !overdue.isEmpty {
            Section("Overdue Today") { slotRows(overdue, occurrencesByKey: occurrencesByKey, now: now) }
        }
        if !laterToday.isEmpty {
            Section("Later Today") { slotRows(laterToday, occurrencesByKey: occurrencesByKey, now: now) }
        }
        if !asNeeded.isEmpty {
            Section("As Needed") {
                ForEach(asNeeded) { schedule in
                    Button {
                        logging = schedule.manualSlot(at: .now, calendar: calendar)
                    } label: {
                        LabeledContent {
                            Text("Log").foregroundStyle(Color.accentColor)
                        } label: {
                            Text(schedule.name).foregroundStyle(.primary)
                        }
                    }
                    .accessibilityLabel(Text("Log \(schedule.name)"))
                    .disabled(store.isUpdating)
                }
            }
        }
        if !completed.isEmpty {
            Section("Today’s Activity") { slotRows(completed, occurrencesByKey: occurrencesByKey, now: now) }
        }
        if !upcoming.isEmpty {
            Section("Next Up") {
                ForEach(upcoming) { slot in
                    if let schedule = records.first(where: { $0.id == slot.scheduleID })?.schedule {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(schedule.name)
                            Text(slot.scheduledAt, format: .dateTime.weekday().month().day().hour().minute())
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func nextRoutines(
        at now: Date, calendar: Calendar, occurrencesByKey: [String: [RoutineOccurrence]]
    ) -> [RoutineOccurrenceSlot] {
        guard let tomorrow = calendar.dateInterval(of: .day, for: now)?.end else { return [] }
        let upcoming = store.schedules.flatMap {
            $0.nextSlots(after: tomorrow.addingTimeInterval(-1), calendar: calendar, limit: 10)
        }.filter { slot in
            occurrencesByKey[slot.id]?.contains { $0.isSkipped || ($0.ingestions?.count ?? 0) > 0 } != true
        }.sorted { ($0.scheduledAt, $0.id) < ($1.scheduledAt, $1.id) }
        return Array(upcoming.prefix(5))
    }

    private func slotRows(
        _ slots: [RoutineOccurrenceSlot], occurrencesByKey: [String: [RoutineOccurrence]], now: Date
    ) -> some View {
        ForEach(slots) { slot in
            if let record = records.first(where: { $0.id == slot.scheduleID }), let schedule = record.schedule {
                row(for: slot, schedule: schedule, unit: record.productUnit, matches: occurrencesByKey[slot.id] ?? [], now: now)
            }
        }
    }

    private func slots(for day: Date, calendar: Calendar) -> [RoutineOccurrenceSlot] {
        let scheduled = records.flatMap { $0.schedule?.slots(on: day, calendar: calendar) ?? [] }
        var byID = Dictionary(scheduled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Keep recorded occurrences visible when a routine's weekdays or time are edited later.
        for occurrence in occurrences {
            guard let id = occurrence.key, let scheduledAt = occurrence.scheduledAt,
                  calendar.isDate(scheduledAt, inSameDayAs: day),
                  let scheduleID = occurrence.routine?.id else { continue }
            byID[id] = RoutineOccurrenceSlot(id: id, scheduleID: scheduleID, scheduledAt: scheduledAt)
        }
        return byID.values.sorted { ($0.scheduledAt, $0.id) < ($1.scheduledAt, $1.id) }
    }

    @ViewBuilder
    private func row(
        for slot: RoutineOccurrenceSlot, schedule: RoutineSchedule, unit: String?, matches: [RoutineOccurrence], now: Date
    ) -> some View {
        let logged = matches.compactMap(\.loggedExperience).first
        let unconfirmed = matches.compactMap(\.unconfirmedExperience).first
        let occurrence = matches.first
        if let logged {
            NavigationLink(value: GlobalNavigationDestination.experience(experience: logged)) {
                routineLabel(schedule.name, slot: slot, status: "Logged")
            }
        } else if let unconfirmed {
            NavigationLink(value: GlobalNavigationDestination.experience(experience: unconfirmed)) {
                routineLabel(schedule.name, slot: slot, status: "Unconfirmed")
            }
        } else if schedule.revision(on: slot.scheduledAt, calendar: RoutineSchedules.calendar)?.preservesProduct == false {
            routineLabel(schedule.name, slot: slot, status: occurrence?.isSkipped == true ? "Skipped" : "Product changed")
        } else {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            layout {
                routineLabel(
                    schedule.name, slot: slot, status: status(for: occurrence, at: now),
                    amount: schedule.amount(for: slot, calendar: RoutineSchedules.calendar), unit: unit
                )
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                HStack(spacing: 12) {
                    if occurrence?.isSkipped == true {
                        Button { update(.reopen, slot: slot) } label: {
                            Text("Reopen").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Reopen \(schedule.name) at \(slot.scheduledAt.formatted(date: .omitted, time: .shortened))"))
                    } else {
                        Button { logging = slot } label: {
                            Text("Log").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Log \(schedule.name) at \(slot.scheduledAt.formatted(date: .omitted, time: .shortened))"))
                        Menu {
                            Button("Skip") { update(.skip, slot: slot) }
                            if !schedule.isAsNeeded, RoutineSchedules.calendar.isDateInToday(slot.scheduledAt), slot.scheduledAt <= now {
                                Button("Snooze 15 Minutes") { update(.snooze, slot: slot) }
                            }
                        } label: {
                            Label("Routine Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(Text("Actions for \(schedule.name) at \(slot.scheduledAt.formatted(date: .omitted, time: .shortened))"))
                    }
                }
                .disabled(store.isUpdating)
            }
        }
    }

    private func routineLabel(
        _ name: String, slot: RoutineOccurrenceSlot, status: String?, amount: Double? = nil, unit: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
            if let status {
                Text("\(slot.scheduledAt.formatted(.dateTime.hour().minute())) · \(status)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(slot.scheduledAt, format: .dateTime.hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let amount, let unit {
                Text("\(amount.formatted(routineAmountFormat)) \(unit)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(for occurrence: RoutineOccurrence?, at now: Date) -> String? {
        if occurrence?.isSkipped == true { return "Skipped" }
        if let snoozedUntil = occurrence?.snoozedUntil, snoozedUntil > now {
            return String(localized: "Snoozed to \(snoozedUntil.formatted(.dateTime.hour().minute()))")
        }
        return nil
    }

    private func update(_ disposition: RoutineSchedules.Disposition, slot: RoutineOccurrenceSlot) {
        error = nil
        Task {
            do {
                try await store.setDisposition(disposition, for: slot)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct RoutineLogSheet: View {
    let record: RoutineRecord?
    let slot: RoutineOccurrenceSlot
    let dismiss: () -> Void
    @State private var amount: Double?
    @State private var isReviewing = false

    var body: some View {
        if let record, let schedule = record.schedule, schedule.productKind == nil {
            ChooseSubstanceScreen()
        } else {
            NavigationStack {
                Form {
                    if let name = record?.customUnit?.nameUnwrapped ?? record?.formulation?.nameUnwrapped {
                        Section("Saved Product") {
                            Text(name)
                            LabeledContent("Amount") {
                                TextField("Amount", value: $amount, format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                if let unit = record?.customUnit?.unitUnwrapped {
                                    Text(unit).foregroundStyle(.secondary)
                                } else if record?.formulation != nil {
                                    Text(Inventory.Use.formulationUnit).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Label("This routine’s saved product is unavailable.", systemImage: "exclamationmark.circle")
                    }
                }
                .navigationTitle(record?.schedule?.name ?? "Log Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") { isReviewing = true }
                            .disabled(arguments.isEmpty)
                    }
                }
                .navigationDestination(isPresented: $isReviewing) {
                    FinishIngestionScreen(ingestions: arguments, dismiss: dismiss)
                }
                .onFirstAppear { amount = record?.schedule?.amount(for: slot, calendar: RoutineSchedules.calendar) }
            }
        }
    }

    private var arguments: [FinishIngestionScreenArguments] {
        guard let amount else { return [] }
        return record?.ingestionArguments(amount: amount) ?? []
    }
}

struct RoutineNotificationReview: ViewModifier {
    @ObservedObject private var store = RoutineSchedules.shared
    @Environment(\.managedObjectContext) private var context
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    private var review: Binding<RoutineOccurrenceSlot?> {
        Binding(
            get: { isEyeOpen ? store.notificationReview : nil },
            set: { store.notificationReview = $0 }
        )
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: review, onDismiss: { Task { await store.refresh() } }) { slot in
                RoutineLogSheet(
                    record: try? RoutineSchedules.record(for: slot.scheduleID, in: context),
                    slot: slot,
                    dismiss: { store.notificationReview = nil }
                )
                .environment(\.routineOccurrenceSlot, slot)
                .environment(\.addIngestionStartTime,
                              RoutineSchedules.calendar.isDateInToday(slot.scheduledAt) ? nil : slot.scheduledAt)
            }
            .alert("Routine Reminder", isPresented: Binding(
                get: { store.notificationError != nil },
                set: { if !$0 { store.notificationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.notificationError ?? "")
            }
    }
}

private extension Calendar {
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
