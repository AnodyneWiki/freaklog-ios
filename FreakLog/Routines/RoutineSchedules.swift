import CoreData
import Foundation
import SwiftUI
import UserNotifications

struct RoutineSchedule: Codable, Hashable, Identifiable {
    enum ProductKind: String, Codable {
        case customUnit, formulation
    }

    struct AnchorDay: Codable, Hashable {
        let year: Int
        let month: Int
        let day: Int

        init(_ date: Date, calendar: Calendar) {
            year = calendar.component(.year, from: date)
            month = calendar.component(.month, from: date)
            day = calendar.component(.day, from: date)
        }

        func date(in calendar: Calendar) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  Self(date, calendar: calendar) == self else { return nil }
            return date
        }
    }

    struct ClockTime: Codable, Hashable, Identifiable {
        var id = UUID()
        var hour: Int
        var minute: Int

        var isValid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
        var minuteOfDay: Int { hour * 60 + minute }

        func date(in calendar: Calendar) -> Date? {
            calendar.nextDate(after: .now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .strict)
        }
    }

    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    // nil means every day. Selected days use Calendar's weekday numbering.
    var weekdays: Set<Int>?
    var reminds = false
    var productKind: ProductKind?
    var productAmount: Double?
    var intervalDays: Int?
    var anchorDay: AnchorDay?
    var additionalTimes: [ClockTime]?

    static func draft(named name: String = "", at date: Date = .now, calendar: Calendar) -> Self {
        Self(
            name: name,
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date),
            anchorDay: AnchorDay(date, calendar: calendar)
        )
    }

    var times: [ClockTime] {
        [ClockTime(id: id, hour: hour, minute: minute)] + (additionalTimes ?? [])
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && times.allSatisfy(\.isValid)
            && Set(times.map(\.id)).count == times.count
            && Set(times.map(\.minuteOfDay)).count == times.count
            && weekdays.map { !$0.isEmpty && $0.allSatisfy { (1...7).contains($0) } } != false
            && (productKind == nil || productAmount.map { $0.isFinite && $0 > 0 } == true)
            && (intervalDays.map { (2...365).contains($0) && weekdays == nil && anchorDay != nil } ?? true)
    }

    func reminderDays() -> [Int?] {
        if let weekdays { return weekdays.sorted().map(Optional.some) }
        return [nil]
    }

    func slot(on day: Date, calendar: Calendar, time: ClockTime? = nil) -> RoutineOccurrenceSlot? {
        let time = time ?? ClockTime(id: id, hour: hour, minute: minute)
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        guard weekdays == nil || components.weekday.map({ weekdays?.contains($0) == true }) == true,
              let year = components.year, let month = components.month, let dayNumber = components.day,
              let scheduledAt = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
              calendar.isDate(day, inSameDayAs: scheduledAt)
        else { return nil }
        if anchorDay != nil {
            guard let offset = offsetFromAnchor(on: day, calendar: calendar), offset >= 0 else { return nil }
            if let intervalDays, !offset.isMultiple(of: intervalDays) { return nil }
        }
        // A civil day and stable time ID identify a slot, even after editing its clock time.
        // Keep the original key for a routine's first time so older logs stay linked.
        let dayKey = "\(id.uuidString).\(year)-\(month)-\(dayNumber)"
        let key = time.id == id ? dayKey : dayKey + "." + time.id.uuidString
        return RoutineOccurrenceSlot(id: key, scheduleID: id, scheduledAt: scheduledAt)
    }

    func slots(on day: Date, calendar: Calendar) -> [RoutineOccurrenceSlot] {
        times.sorted { $0.minuteOfDay < $1.minuteOfDay }.compactMap { slot(on: day, calendar: calendar, time: $0) }
    }

    func nextIntervalSlots(after date: Date, calendar: Calendar, limit: Int) -> [RoutineOccurrenceSlot] {
        guard let intervalDays, let anchor = anchorDay?.date(in: calendar),
              let offset = offsetFromAnchor(on: date, calendar: calendar) else { return [] }
        let nextOffset = offset < 0 ? 0 : (offset / intervalDays) * intervalDays
        let days = (0...limit).compactMap { index in
            calendar.date(byAdding: .day, value: nextOffset + index * intervalDays, to: anchor)
        }
        return Array(days.flatMap { slots(on: $0, calendar: calendar) }.filter { $0.scheduledAt > date }.prefix(limit))
    }

    private func offsetFromAnchor(on date: Date, calendar: Calendar) -> Int? {
        guard let anchor = anchorDay?.date(in: calendar) else { return nil }
        return calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day
    }
}

struct RoutineOccurrenceSlot: Identifiable {
    let id: String
    let scheduleID: UUID
    let scheduledAt: Date
}

extension RoutineRecord {
    var schedule: RoutineSchedule? {
        guard let scheduleData,
              let schedule = try? JSONDecoder().decode(RoutineSchedule.self, from: scheduleData),
              schedule.id == id, schedule.isValid
        else { return nil }
        return schedule
    }
}

extension RoutineOccurrence {
    var loggedExperience: Experience? {
        let ingestions = ingestions?.allObjects as? [Ingestion] ?? []
        return ingestions.sorted { $0.timeUnwrapped < $1.timeUnwrapped }.compactMap(\.experience).first
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

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func refresh(askingPermission: Bool = false) async {
        guard !isUpdating, !PersistenceController.isJournalOperationInProgress else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try Self.importLegacySchedulesIfNeeded()
            try reload(in: PersistenceController.shared.viewContext)
            loadError = nil
            await reconcileReminders(askingPermission: askingPermission)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func save(_ schedule: RoutineSchedule, productID: NSManagedObjectID?) async throws {
        guard !isUpdating else { throw StorageError.busy }
        guard schedule.isValid else { throw StorageError.invalidSchedule }
        isUpdating = true
        defer { isUpdating = false }

        let context = try PersistenceController.shared.journalEditContext()
        let original = try Self.record(for: schedule.id, in: context)
        let wasReminding = original?.schedule?.reminds == true
        let record = original ?? RoutineRecord(context: context)
        record.id = schedule.id
        record.scheduleData = try JSONEncoder().encode(schedule)
        record.customUnit = nil
        record.formulation = nil
        if let productKind = schedule.productKind {
            guard let productID, let product = try? context.existingObject(with: productID), !product.isDeleted else {
                throw StorageError.missingProduct
            }
            switch productKind {
            case .customUnit:
                guard let unit = product as? CustomUnit, !unit.isArchived else { throw StorageError.missingProduct }
                record.customUnit = unit
            case .formulation:
                guard let formulation = product as? Formulation, !formulation.componentsSorted.isEmpty else {
                    throw StorageError.missingProduct
                }
                record.formulation = formulation
            }
        }
        try context.save()
        try reload(in: context)
        await reconcileReminders(askingPermission: schedule.reminds && !wasReminding)
    }

    func delete(_ id: UUID) async throws {
        guard !isUpdating else { throw StorageError.busy }
        isUpdating = true
        defer { isUpdating = false }
        let context = try PersistenceController.shared.journalEditContext()
        if let record = try Self.record(for: id, in: context) {
            context.delete(record)
            try context.save()
        }
        try reload(in: context)
        await reconcileReminders(askingPermission: false)
    }

    func setDisposition(_ disposition: Disposition, for slot: RoutineOccurrenceSlot) async throws {
        guard !isUpdating else { throw StorageError.busy }
        isUpdating = true
        defer { isUpdating = false }

        let context = try PersistenceController.shared.journalEditContext()
        let occurrence = try Self.occurrence(for: slot, in: context)
        guard occurrence.ingestions?.count ?? 0 == 0 else { throw StorageError.alreadyLogged }
        switch disposition {
        case .skip:
            occurrence.isSkipped = true
            occurrence.snoozedUntil = nil
        case .snooze:
            occurrence.isSkipped = false
            occurrence.snoozedUntil = Date().addingTimeInterval(15 * 60)
        case .reopen:
            occurrence.isSkipped = false
            occurrence.snoozedUntil = nil
        }
        try context.save()
        try reload(in: context)
        await reconcileReminders(askingPermission: disposition == .snooze)
    }

    enum Disposition: Equatable {
        case skip, snooze, reopen
    }

    static func record(for id: UUID, in context: NSManagedObjectContext) throws -> RoutineRecord? {
        let request = RoutineRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func occurrence(for slot: RoutineOccurrenceSlot, in context: NSManagedObjectContext) throws -> RoutineOccurrence {
        guard let routine = try record(for: slot.scheduleID, in: context), routine.schedule != nil else {
            throw StorageError.missingRoutine
        }
        let request = RoutineOccurrence.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", slot.id)
        let existing = try context.fetch(request)
        if let recorded = existing.first(where: { ($0.ingestions?.count ?? 0) > 0 }) ?? existing.first {
            return recorded
        }
        let occurrence = RoutineOccurrence(context: context)
        occurrence.key = slot.id
        occurrence.scheduledAt = slot.scheduledAt
        occurrence.routine = routine
        return occurrence
    }

    static func stageLog(for slot: RoutineOccurrenceSlot, in context: NSManagedObjectContext) throws -> RoutineOccurrence? {
        let occurrence = try occurrence(for: slot, in: context)
        // Saving happens synchronously on the main actor, in the same transaction as these links.
        guard occurrence.ingestions?.count ?? 0 == 0 else { return nil }
        guard !occurrence.isSkipped else { throw StorageError.skipped }
        occurrence.snoozedUntil = nil
        return occurrence
    }

    static func importLegacySchedulesIfNeeded() throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PersistenceController.didMigrateRoutineSchedulesKey) else { return }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let file = support.appendingPathComponent("RoutineSchedules").appendingPathComponent("schedules.json")
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            defaults.set(true, forKey: PersistenceController.didMigrateRoutineSchedulesKey)
            return
        } catch {
            throw StorageError.unreadable
        }
        let schedules: [RoutineSchedule]
        do {
            schedules = try JSONDecoder().decode([RoutineSchedule].self, from: data)
            guard schedules.allSatisfy(\.isValid), Set(schedules.map(\.id)).count == schedules.count else {
                throw StorageError.unreadable
            }
        } catch {
            throw StorageError.unreadable
        }
        let context = try PersistenceController.shared.journalEditContext()
        for schedule in schedules where try record(for: schedule.id, in: context) == nil {
            let record = RoutineRecord(context: context)
            record.id = schedule.id
            record.scheduleData = try JSONEncoder().encode(schedule)
        }
        if context.hasChanges { try context.save() }
        defaults.set(true, forKey: PersistenceController.didMigrateRoutineSchedulesKey)
    }

    private func reload(in context: NSManagedObjectContext) throws {
        let saved = try context.fetch(RoutineRecord.fetchRequest())
        schedules = saved.compactMap(\.schedule).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

        let allPending = await center.pendingNotificationRequests()
        guard !PersistenceController.isJournalOperationInProgress else { return }
        let pending = allPending.filter { $0.identifier.hasPrefix(Self.reminderPrefix) }
        let canSchedule = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        let desired: [UNNotificationRequest]
        do {
            desired = canSchedule ? try reminderRequests(existingOtherRequests: allPending.count - pending.count) : []
        } catch {
            reminderError = "Some reminders couldn’t be read."
            return
        }
        let desiredIDs = Set(desired.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter { !desiredIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)

        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for request in desired {
            let old = existing[request.identifier]?.trigger as? UNCalendarNotificationTrigger
            let new = request.trigger as? UNCalendarNotificationTrigger
            if let old, let new, old.dateComponents == new.dateComponents, old.repeats == new.repeats { continue }
            do {
                try await center.add(request)
            } catch {
                reminderError = "Some reminders couldn’t be scheduled."
            }
        }
        let active = Set(await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix(Self.reminderPrefix)
        })
        if desiredIDs != active {
            reminderError = "Some reminders couldn’t be updated."
        }
    }

    private func reminderRequests(existingOtherRequests: Int) throws -> [UNNotificationRequest] {
        let context = try PersistenceController.shared.journalEditContext()
        try reload(in: context)
        let calendar = Self.calendar
        let now = Date()
        let request = RoutineOccurrence.fetchRequest()
        request.predicate = NSPredicate(format: "snoozedUntil > %@ OR scheduledAt >= %@", now as NSDate, calendar.startOfDay(for: now) as NSDate)
        let records = try context.fetch(request)
        let suppressed = Set(records.filter {
            $0.isSkipped || ($0.ingestions?.count ?? 0) > 0 || ($0.snoozedUntil ?? .distantPast) > now
        }.compactMap(\.key))
        var repeating: [UNNotificationRequest] = []
        var oneTime: [(id: String, date: Date)] = records.compactMap { occurrence in
            guard let id = occurrence.key, let alert = occurrence.snoozedUntil, alert > now,
                  !occurrence.isSkipped, (occurrence.ingestions?.count ?? 0) == 0 else { return nil }
            return (id + ".snoozed", alert)
        }
        for schedule in schedules where schedule.reminds {
            if schedule.intervalDays != nil {
                oneTime += schedule.nextIntervalSlots(after: now, calendar: calendar, limit: 12)
                    .filter { !suppressed.contains($0.id) }
                    .map { ($0.id + ".interval", $0.scheduledAt) }
                continue
            }
            for time in schedule.times {
                for weekday in schedule.reminderDays() {
                    let date = DateComponents(hour: time.hour, minute: time.minute, weekday: weekday)
                    let id = time.id.uuidString + "." + (weekday.map(String.init) ?? "daily")
                    if let next = calendar.nextDate(after: now, matching: date, matchingPolicy: .nextTime),
                       let slot = schedule.slot(on: next, calendar: calendar, time: time), suppressed.contains(slot.id) {
                        // A calendar repeat can't omit one day. Queue upcoming dates without that occurrence.
                        var previous = next
                        for _ in 0..<12 {
                            guard let following = calendar.nextDate(after: previous, matching: date, matchingPolicy: .nextTime),
                                  let followingSlot = schedule.slot(on: following, calendar: calendar, time: time) else { break }
                            if !suppressed.contains(followingSlot.id) {
                                oneTime.append((followingSlot.id + ".regular", following))
                            }
                            previous = following
                        }
                    } else {
                        repeating.append(reminder(id: id, date: date, repeats: true))
                    }
                }
            }
        }
        // Keep the nearest dates when many routines compete for the system's pending requests.
        let available = max(0, 64 - existingOtherRequests - repeating.count)
        return repeating + oneTime.sorted { $0.date < $1.date }.prefix(available).map { entry in
            let date = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.date)
            return reminder(id: entry.id, date: date, repeats: false)
        }
    }

    private func reminder(id: String, date: DateComponents, repeats: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Routine Reminder")
        content.body = String(localized: "A scheduled routine is due.")
        content.sound = .default
        return UNNotificationRequest(
            identifier: Self.reminderPrefix + id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: repeats))
    }

    enum StorageError: LocalizedError {
        case busy, unreadable, invalidSchedule, missingRoutine, missingProduct, alreadyLogged, skipped

        var errorDescription: String? {
            switch self {
            case .busy: "Routines are updating. Try again in a moment."
            case .unreadable: "Saved routines couldn’t be read."
            case .invalidSchedule: "Enter a name, select at least one day, and check the product amount."
            case .missingRoutine: "This routine is no longer available."
            case .missingProduct: "Choose an available product for this routine."
            case .alreadyLogged: "This occurrence has already been logged."
            case .skipped: "Reopen this occurrence before logging it."
            }
        }
    }
}

private struct RoutineOccurrenceSlotKey: EnvironmentKey {
    static let defaultValue: RoutineOccurrenceSlot? = nil
}

extension EnvironmentValues {
    var routineOccurrenceSlot: RoutineOccurrenceSlot? {
        get { self[RoutineOccurrenceSlotKey.self] }
        set { self[RoutineOccurrenceSlotKey.self] = newValue }
    }
}
