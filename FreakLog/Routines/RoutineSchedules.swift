import Foundation
import SwiftUI
import UserNotifications

struct RoutineSchedule: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    // nil means every day. Selected days use Calendar's weekday numbering.
    var weekdays: Set<Int>?
    var reminds = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (0..<24).contains(hour)
            && (0..<60).contains(minute)
            && weekdays.map { !$0.isEmpty && $0.allSatisfy { (1...7).contains($0) } } != false
    }

    func reminderDays() -> [Int?] {
        if let weekdays {
            return weekdays.sorted().map(Optional.some)
        }
        return [nil]
    }
}

@MainActor
final class RoutineSchedules: ObservableObject {
    static let shared = RoutineSchedules()

    private static let reminderPrefix = "freaklog.routine."
    @Published private(set) var schedules: [RoutineSchedule] = []
    @Published private(set) var isUpdating = false
    @Published private(set) var loadError: String?
    @Published private(set) var reminderError: String?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private var hasLoaded = false

    func refresh(askingPermission: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        guard loadIfNeeded() else { return }
        await reconcileReminders(askingPermission: askingPermission)
    }

    func save(_ schedule: RoutineSchedule) async throws {
        guard schedule.isValid else { throw StorageError.invalidSchedule }
        try beginUpdate()
        defer { isUpdating = false }

        var updated = schedules
        let wasReminding: Bool
        if let index = updated.firstIndex(where: { $0.id == schedule.id }) {
            wasReminding = updated[index].reminds
            updated[index] = schedule
        } else {
            wasReminding = false
            updated.append(schedule)
        }
        try write(updated)
        await reconcileReminders(askingPermission: schedule.reminds && !wasReminding)
    }

    func delete(_ id: UUID) async throws {
        try beginUpdate()
        defer { isUpdating = false }
        try write(schedules.filter { $0.id != id })
        await reconcileReminders(askingPermission: false)
    }

    private func beginUpdate() throws {
        guard !isUpdating else { throw StorageError.busy }
        guard loadIfNeeded() else { throw StorageError.unreadable }
        isUpdating = true
    }

    // An unreadable file stays untouched. A later refresh can retry reading it.
    private func loadIfNeeded() -> Bool {
        if hasLoaded { return true }
        do {
            let url = try fileURL()
            do {
                let saved = try JSONDecoder().decode([RoutineSchedule].self, from: Data(contentsOf: url))
                guard saved.allSatisfy(\.isValid), Set(saved.map(\.id)).count == saved.count else {
                    throw StorageError.unreadable
                }
                schedules = saved
            } catch CocoaError.fileReadNoSuchFile {
                schedules = []
            }
            hasLoaded = true
            loadError = nil
            return true
        } catch {
            loadError = StorageError.unreadable.localizedDescription
            return false
        }
    }

    private func write(_ updated: [RoutineSchedule]) throws {
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            schedules = updated
        } catch {
            throw StorageError.writeFailed
        }
    }

    private func fileURL() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("RoutineSchedules", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory.appendingPathComponent("schedules.json")
    }

    private func reconcileReminders(askingPermission: Bool) async {
        let center = UNUserNotificationCenter.current()
        reminderError = nil
        authorization = await center.notificationSettings().authorizationStatus
        if askingPermission, authorization == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                reminderError = "Couldn’t ask for notification permission."
            }
            authorization = await center.notificationSettings().authorizationStatus
        }

        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.reminderPrefix) }
        let canSchedule = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        let desired = canSchedule ? reminderRequests() : []
        let desiredIDs = Set(desired.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter { !desiredIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)

        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for request in desired {
            let old = existing[request.identifier]?.trigger as? UNCalendarNotificationTrigger
            let new = request.trigger as? UNCalendarNotificationTrigger
            if old?.dateComponents == new?.dateComponents && old?.repeats == true { continue }
            do {
                try await center.add(request)
            } catch {
                reminderError = "Some reminders couldn’t be scheduled."
            }
        }

        // Some versions of iOS can limit the pending notifications an app keeps.
        let active = Set(await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix(Self.reminderPrefix)
        })
        if desiredIDs != active {
            reminderError = "Some reminders couldn’t be updated."
        }
    }

    private func reminderRequests() -> [UNNotificationRequest] {
        schedules.filter(\.reminds).flatMap { schedule in
            schedule.reminderDays().map { weekday in
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Routine Reminder")
                content.body = String(localized: "A scheduled routine is due.")
                content.sound = .default
                // Match local wall clock time, including after a time zone change.
                let date = DateComponents(hour: schedule.hour, minute: schedule.minute, weekday: weekday)
                let identifier = Self.reminderPrefix + schedule.id.uuidString + "." + (weekday.map(String.init) ?? "daily")
                return UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                )
            }
        }
    }

    private enum StorageError: LocalizedError {
        case busy, unreadable, invalidSchedule, writeFailed

        var errorDescription: String? {
            switch self {
            case .busy: "Routines are updating. Try again in a moment."
            case .unreadable: "Saved routines couldn’t be read."
            case .invalidSchedule: "Enter a name and select at least one day."
            case .writeFailed: "Changes couldn’t be saved."
            }
        }
    }
}
