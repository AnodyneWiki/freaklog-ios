import SwiftUI
import UserNotifications

struct JournalReminderDraft: Identifiable {
    enum Source: String {
        case custom = "Custom Time"
        case timeline = "Timeline"
        case timedNote = "Timed Note"
    }

    let id: String
    let date: Date
    let source: Source

    init(date: Date = .now.addingTimeInterval(3600), source: Source = .custom, id: String = UUID().uuidString) {
        self.id = id
        self.date = date
        self.source = source
    }
}

@MainActor
final class JournalReminders {
    static let shared = JournalReminders()
    nonisolated static let prefix = "journal-reminder."

    private let center = UNUserNotificationCenter.current()
    private var isSaving = false

    func pending() async -> [JournalReminderDraft] {
        await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(Self.prefix),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            let source = (request.content.userInfo["source"] as? String).flatMap(JournalReminderDraft.Source.init(rawValue:))
            return JournalReminderDraft(date: date, source: source ?? .custom,
                                        id: String(request.identifier.dropFirst(Self.prefix.count)))
        }
        .sorted { $0.date < $1.date }
    }

    func save(_ draft: JournalReminderDraft, at date: Date) async throws {
        guard !isSaving else { throw ReminderError.busy }
        guard date > .now else { throw ReminderError.pastDate }
        isSaving = true
        defer { isSaving = false }

        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .ephemeral, .provisional:
            break
        case .notDetermined:
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw ReminderError.permission }
        default:
            throw ReminderError.permission
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let dateWithSeconds = Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
        let components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: dateWithSeconds)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let fireDate = trigger.nextTriggerDate(), fireDate > .now else { throw ReminderError.pastDate }

        let identifier = Self.prefix + draft.id
        let existing = await center.pendingNotificationRequests()
        guard existing.count < 64 || existing.contains(where: { $0.identifier == identifier }) else { throw ReminderError.full }

        let content = UNMutableNotificationContent()
        content.title = "Journal Reminder"
        content.body = "Open your journal when you’re ready."
        content.sound = .default
        content.userInfo = ["source": draft.source.rawValue]
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        guard await center.pendingNotificationRequests().contains(where: { $0.identifier == identifier }) else {
            throw ReminderError.unavailable
        }
    }

    func cancel(_ reminder: JournalReminderDraft) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.prefix + reminder.id])
    }

    private enum ReminderError: LocalizedError {
        case busy, permission, pastDate, full, unavailable

        var errorDescription: String? {
            switch self {
            case .busy: "Wait for the current reminder to finish saving."
            case .permission: "Allow notifications for FreakLog in Settings to schedule reminders."
            case .pastDate: "Choose a time in the future."
            case .full: "There are too many pending reminders. Remove one before scheduling another."
            case .unavailable: "The reminder couldn’t be scheduled."
            }
        }
    }
}

struct JournalRemindersScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: [JournalReminderDraft] = []
    @State private var isLoading = true
    @State private var draft: JournalReminderDraft?

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                } else if pending.isEmpty {
                    Text("No pending reminders").foregroundStyle(.secondary)
                }
                ForEach(pending) { reminder in
                    Button {
                        draft = reminder
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reminder.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                    .foregroundStyle(.primary)
                                Text(reminder.source.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            JournalReminders.shared.cancel(reminder)
                            pending.removeAll { $0.id == reminder.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Pending")
            } footer: {
                Text("Reminders are saved on this device. Notifications leave out journal details.")
            }
        }
        .navigationTitle("Journal Reminders")
        .toolbar {
            Button { draft = JournalReminderDraft() } label: {
                Label("Add Reminder", systemImage: "plus")
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(item: $draft, onDismiss: { Task { await refresh() } }) { reminder in
            JournalReminderEditor(draft: reminder, isEditing: pending.contains { $0.id == reminder.id })
        }
    }

    private func refresh() async {
        pending = await JournalReminders.shared.pending()
        isLoading = false
    }
}

struct JournalReminderEditor: View {
    let draft: JournalReminderDraft
    var isEditing: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(draft: JournalReminderDraft, isEditing: Bool = false) {
        self.draft = draft
        self.isEditing = isEditing
        _date = State(initialValue: draft.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Remind Me", selection: $date)
                    if draft.source != .custom {
                        LabeledContent("From", value: draft.source.rawValue)
                    }
                } footer: {
                    Text(draft.source == .custom
                         ? "The notification leaves out journal details."
                         : "The reminder stays at this time if you edit the journal later. The notification leaves out journal details.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if isEditing {
                    Button("Delete Reminder", role: .destructive) {
                        JournalReminders.shared.cancel(draft)
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().accessibilityLabel("Saving Reminder")
                    } else {
                        Button("Save") { Task { await save() } }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await JournalReminders.shared.save(draft, at: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
