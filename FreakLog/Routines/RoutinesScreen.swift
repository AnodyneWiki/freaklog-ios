import SwiftUI
import UIKit

struct RoutinesScreen: View {
    @ObservedObject private var store = RoutineSchedules.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: RoutineSchedule?

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
                                    Text(scheduleSummary(schedule))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Routines are stored on this device. Reminders use a generic message.")
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
                    let time = Calendar.current.dateComponents([.hour, .minute], from: .now)
                    selection = RoutineSchedule(name: "", hour: time.hour ?? 0, minute: time.minute ?? 0)
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

    private func scheduleSummary(_ schedule: RoutineSchedule) -> String {
        let calendar = Calendar.current
        let time = calendar.nextDate(
            after: .now, matching: DateComponents(hour: schedule.hour, minute: schedule.minute), matchingPolicy: .strict)
        let formattedTime = time?.formatted(date: .omitted, time: .shortened) ?? "–"
        if let weekdays = schedule.weekdays {
            let symbols = calendar.shortWeekdaySymbols
            let days = calendar.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }
            return String(localized: "\(days.formatted(.list(type: .and))) at \(formattedTime)")
        }
        return String(localized: "Every day at \(formattedTime)")
    }
}

private struct RoutineScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RoutineSchedules
    @State private var schedule: RoutineSchedule
    @State private var time: Date
    @State private var showsDeleteConfirmation = false
    @State private var error: String?
    let isNew: Bool

    init(schedule: RoutineSchedule, isNew: Bool, store: RoutineSchedules) {
        _schedule = State(initialValue: schedule)
        _time = State(initialValue: Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: schedule.hour, minute: schedule.minute),
            matchingPolicy: .strict
        ) ?? .now)
        self.isNew = isNew
        self.store = store
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
                    Picker("Repeat", selection: repeatsDaily) {
                        Text("Every Day").tag(true)
                        Text("Selected Days").tag(false)
                    }
                    if schedule.weekdays != nil {
                        ForEach(Calendar.current.orderedWeekdays, id: \.self) { weekday in
                            Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: selection(for: weekday))
                        }
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
                    Button("Save", action: save).disabled(store.isUpdating || !schedule.isValid)
                }
            }
            .confirmationDialog("Delete this routine?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive, action: delete)
            }
        }
        .interactiveDismissDisabled(store.isUpdating)
    }

    private var repeatsDaily: Binding<Bool> {
        Binding(
            get: { schedule.weekdays == nil },
            set: { schedule.weekdays = $0 ? nil : [Calendar.current.component(.weekday, from: .now)] }
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

    private func save() {
        error = nil
        var updated = schedule
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        updated.hour = components.hour ?? schedule.hour
        updated.minute = components.minute ?? schedule.minute
        Task {
            do {
                try await store.save(updated)
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

private extension Calendar {
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
