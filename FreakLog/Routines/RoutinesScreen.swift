import CoreData
import SwiftUI
import UIKit

struct RoutinesScreen: View {
    @ObservedObject private var store = RoutineSchedules.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: RoutineSchedule?
    @AppStorage(PersistenceController.showsDueTodayKey) private var showsDueToday = false

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
                            selection = schedule
                        } label: {
                            LabeledContent {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(schedule.name).foregroundStyle(.primary)
                                    Text(schedule.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    NavigationLink("Due Today") { RoutineDayScreen() }
                    Toggle("Show Due Today in Journal", isOn: $showsDueToday)
                } footer: {
                    Text("Reminders use a generic message.")
                }

                if store.authorization == .denied, store.schedules.contains(where: \.reminds) {
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
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
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
                store: store
            )
        }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

extension RoutineSchedule {
    @MainActor var summary: String {
        let calendar = RoutineSchedules.calendar
        let times = times.sorted { $0.minuteOfDay < $1.minuteOfDay }
        let formattedTime = times.compactMap { $0.date(in: calendar)?.formatted(date: .omitted, time: .shortened) }
            .formatted(.list(type: .and))
        if let interval = intervalDays {
            return String(localized: "Every \(interval) days at \(formattedTime)")
        }
        if let weekdays {
            let symbols = calendar.shortWeekdaySymbols
            let days = calendar.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }
            return String(localized: "\(days.formatted(.list(type: .and))) at \(formattedTime)")
        }
        return String(localized: "Every day at \(formattedTime)")
    }
}

struct RoutineScheduleEditor: View {
    private enum Frequency: Hashable {
        case daily, selectedDays, interval
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
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                    }
                }

                Section {
                    TextField("Routine Name", text: $schedule.name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Schedule") {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    ForEach(schedule.additionalTimes ?? []) { entry in
                        HStack {
                            DatePicker("Time", selection: timeBinding(for: entry), displayedComponents: .hourAndMinute)
                            Button(role: .destructive) {
                                schedule.additionalTimes?.removeAll { $0.id == entry.id }
                            } label: {
                                Label("Remove Time", systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button(action: addTime) {
                        Label("Add Time", systemImage: "plus.circle")
                    }
                    if Set(preparedSchedule.times.map(\.minuteOfDay)).count != preparedSchedule.times.count {
                        Text("Choose a different time for each occurrence.").foregroundStyle(.secondary)
                    }
                    Picker("Repeat", selection: frequency) {
                        Text("Every Day").tag(Frequency.daily)
                        Text("Selected Days").tag(Frequency.selectedDays)
                        Text("Fixed Interval").tag(Frequency.interval)
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
                        DatePicker("First Day", selection: firstDay, displayedComponents: .date)
                    }
                }

                Section("Saved Product") {
                    Picker("Product", selection: $productID) {
                        Text("Choose When Logging").tag(nil as NSManagedObjectID?)
                        ForEach(customUnits) { unit in
                            Text(unit.nameUnwrapped).tag(Optional(unit.objectID))
                        }
                        ForEach(formulations) { formulation in
                            Text(formulation.nameUnwrapped).tag(Optional(formulation.objectID))
                        }
                    }
                    if let productID {
                        if showsProductLink, let product = selectedProduct {
                            NavigationLink {
                                ProductDetailScreen(product: product)
                            } label: {
                                Label("View Product", systemImage: "shippingbox")
                            }
                        }
                        LabeledContent("Amount") {
                            TextField("Amount", value: $schedule.productAmount, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                            if let unit = customUnits.first(where: { $0.objectID == productID })?.unitUnwrapped {
                                Text(unit).foregroundStyle(.secondary)
                            } else if formulations.contains(where: { $0.objectID == productID }) {
                                Text(Inventory.Use.formulationUnit).foregroundStyle(.secondary)
                            }
                        }
                    } else if schedule.productKind != nil {
                        Text("The saved product is unavailable. Choose another product or choose when logging.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Remind Me", isOn: $schedule.reminds)
                } footer: {
                    Text("Reminders omit the routine name.")
                }

                if !isNew {
                    Section {
                        Button("Delete Routine", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
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
                    Button("Save", action: save).disabled(store.isUpdating || !preparedSchedule.isValid)
                }
            }
            .confirmationDialog("Delete this routine?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive, action: delete)
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

    private var frequency: Binding<Frequency> {
        Binding(
            get: {
                if schedule.intervalDays != nil { return .interval }
                return schedule.weekdays == nil ? .daily : .selectedDays
            },
            set: { value in
                let calendar = RoutineSchedules.calendar
                if schedule.intervalDays != nil, value != .interval {
                    schedule.anchorDay = .init(.now, calendar: calendar)
                }
                schedule.weekdays = value == .selectedDays ? [calendar.component(.weekday, from: .now)] : nil
                schedule.intervalDays = value == .interval ? 2 : nil
                if value == .interval {
                    schedule.anchorDay = .init(.now, calendar: calendar)
                }
            }
        )
    }

    private var firstDay: Binding<Date> {
        Binding(
            get: { schedule.anchorDay?.date(in: RoutineSchedules.calendar) ?? .now },
            set: { schedule.anchorDay = .init($0, calendar: RoutineSchedules.calendar) }
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
    @ObservedObject private var store = RoutineSchedules.shared
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "scheduledAt", ascending: true)])
    private var occurrences: FetchedResults<RoutineOccurrence>
    @FetchRequest(sortDescriptors: []) private var records: FetchedResults<RoutineRecord>
    @State private var selectedDay = Date()
    @State private var logging: RoutineOccurrenceSlot?
    @State private var error: String?

    var body: some View {
        List {
            DatePicker("Date", selection: $selectedDay, in: ...Date(), displayedComponents: .date)
            if let error = error ?? store.loadError ?? store.reminderError {
                Label(error, systemImage: "exclamationmark.circle")
            }
            if slots.isEmpty {
                Text("No routines for this day").foregroundStyle(.secondary)
            }
            ForEach(slots) { slot in
                if let record = records.first(where: { $0.id == slot.scheduleID }), let schedule = record.schedule {
                    row(for: slot, schedule: schedule)
                }
            }
        }
        .navigationTitle(RoutineSchedules.calendar.isDateInToday(selectedDay) ? "Due Today" : "Routine History")
        .task { await store.refresh() }
        .sheet(item: $logging, onDismiss: { Task { await store.refresh() } }) { slot in
            RoutineLogSheet(
                record: records.first(where: { $0.id == slot.scheduleID }),
                dismiss: { logging = nil }
            )
            .environment(\.routineOccurrenceSlot, slot)
            .environment(\.addIngestionStartTime,
                          RoutineSchedules.calendar.isDateInToday(slot.scheduledAt) ? nil : slot.scheduledAt)
        }
    }

    private var slots: [RoutineOccurrenceSlot] {
        let calendar = RoutineSchedules.calendar
        let scheduled = records.flatMap { $0.schedule?.slots(on: selectedDay, calendar: calendar) ?? [] }
        var byID = Dictionary(scheduled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Keep recorded occurrences visible when a routine's weekdays or time are edited later.
        for occurrence in occurrences {
            guard let id = occurrence.key, let scheduledAt = occurrence.scheduledAt,
                  calendar.isDate(scheduledAt, inSameDayAs: selectedDay),
                  let scheduleID = occurrence.routine?.id else { continue }
            byID[id] = RoutineOccurrenceSlot(id: id, scheduleID: scheduleID, scheduledAt: scheduledAt)
        }
        return byID.values.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    @ViewBuilder
    private func row(for slot: RoutineOccurrenceSlot, schedule: RoutineSchedule) -> some View {
        let matches = occurrences.filter { $0.key == slot.id }
        let logged = matches.compactMap(\.loggedExperience).first
        let occurrence = matches.first
        if let logged {
            NavigationLink(value: GlobalNavigationDestination.experience(experience: logged)) {
                routineLabel(schedule.name, slot: slot, status: "Logged")
            }
        } else {
            HStack {
                routineLabel(schedule.name, slot: slot, status: status(for: occurrence))
                Spacer()
                if occurrence?.isSkipped == true {
                    Button("Reopen") { update(.reopen, slot: slot) }
                        .buttonStyle(.borderless)
                        .disabled(store.isUpdating)
                } else {
                    Button("Log") { logging = slot }
                        .buttonStyle(.borderless)
                    Menu {
                        Button("Skip") { update(.skip, slot: slot) }
                        if RoutineSchedules.calendar.isDateInToday(selectedDay), slot.scheduledAt <= .now {
                            Button("Snooze 15 Minutes") { update(.snooze, slot: slot) }
                        }
                    } label: {
                        Label("Routine Actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                    .disabled(store.isUpdating)
                }
            }
        }
    }

    private func routineLabel(_ name: String, slot: RoutineOccurrenceSlot, status: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
            if let status {
                Text("\(slot.scheduledAt.formatted(.dateTime.hour().minute())) · \(status)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(slot.scheduledAt, format: .dateTime.hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(for occurrence: RoutineOccurrence?) -> String? {
        if occurrence?.isSkipped == true { return "Skipped" }
        if let snoozedUntil = occurrence?.snoozedUntil, snoozedUntil > .now {
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
    let dismiss: () -> Void
    @State private var amount: Double?
    @State private var isReviewing = false

    var body: some View {
        if let record, let schedule = record.schedule, schedule.productKind == nil {
            ChooseSubstanceScreen(usesShortcutPrefill: false)
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
                .onFirstAppear { amount = record?.schedule?.productAmount }
            }
        }
    }

    private var arguments: [FinishIngestionScreenArguments] {
        guard let record, let amount, amount.isFinite, amount > 0 else { return [] }
        if let unit = record.customUnit, !unit.isArchived {
            return [FinishIngestionScreenArguments(
                substanceName: unit.substanceNameUnwrapped,
                administrationRoute: unit.administrationRouteUnwrapped,
                dose: amount,
                units: unit.originalUnitUnwrapped,
                isEstimate: false,
                estimatedDoseStandardDeviation: nil,
                customUnit: unit)]
        }
        return record.formulation?.ingestionArguments(amount: amount) ?? []
    }
}

private extension Calendar {
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
