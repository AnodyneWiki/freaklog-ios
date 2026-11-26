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
        var productAmount: Double?

        var isValid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
        var minuteOfDay: Int { hour * 60 + minute }

        func date(in calendar: Calendar) -> Date? {
            calendar.nextDate(after: .now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .strict)
        }
    }

    struct PausePeriod: Codable, Hashable {
        let startedAt: Date
        var endedAt: Date?

        func contains(_ date: Date) -> Bool {
            date >= startedAt && (endedAt.map { date < $0 } ?? true)
        }
    }

    struct Revision: Codable, Hashable {
        let effectiveBefore: AnchorDay
        let schedule: RoutineSchedule
        var preservesProduct: Bool
    }

    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    // Selected days use Calendar's weekday numbering.
    var weekdays: Set<Int>?
    var reminds = false
    var productKind: ProductKind?
    var productAmount: Double?
    var intervalDays: Int?
    var anchorDay: AnchorDay?
    var additionalTimes: [ClockTime]?
    var endDay: AnchorDay?
    var pauses: [PausePeriod]?
    var monthlyDay: Int?
    var asNeeded: Bool?
    var revisions: [Revision]?

    var isAsNeeded: Bool { asNeeded == true }

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
            && productAmount.map { $0.isFinite && $0 > 0 } != false
            && times.allSatisfy { $0.productAmount.map { $0.isFinite && $0 > 0 } != false }
            && (intervalDays.map { (2...365).contains($0) && anchorDay != nil } ?? true)
            && (monthlyDay.map { (1...31).contains($0) && weekdays == nil && intervalDays == nil } ?? true)
            && (!isAsNeeded || (!reminds && intervalDays == nil && monthlyDay == nil && weekdays == nil))
    }

    var isPaused: Bool { pauses?.last.map { $0.endedAt == nil } ?? false }

    func isAvailable(forRemindersAfter date: Date, calendar: Calendar) -> Bool {
        !isAsNeeded && !isPaused && endDay?.date(in: calendar).map { $0 >= calendar.startOfDay(for: date) } != false
    }

    func canLogAsNeeded(at date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return isAsNeeded && !isPaused && !isPastEnd(on: day, calendar: calendar)
            && anchorDay?.date(in: calendar).map { $0 <= day } != false
    }

    func manualSlot(at date: Date, calendar: Calendar) -> RoutineOccurrenceSlot? {
        guard canLogAsNeeded(at: date, calendar: calendar) else { return nil }
        return RoutineOccurrenceSlot(id: "\(id.uuidString).manual.\(UUID().uuidString)", scheduleID: id, scheduledAt: date)
    }

    mutating func setPaused(_ paused: Bool, at date: Date = .now) {
        guard paused != isPaused else { return }
        var periods = pauses ?? []
        if paused {
            periods.append(PausePeriod(startedAt: date))
        } else if let last = periods.indices.last {
            periods[last].endedAt = max(periods[last].startedAt, date)
        }
        pauses = periods
    }

    func duplicate(at date: Date = .now, calendar: Calendar) -> Self {
        var copy = self
        copy.id = UUID()
        copy.name = String(localized: "Copy of \(name)")
        copy.additionalTimes = additionalTimes?.map {
            ClockTime(hour: $0.hour, minute: $0.minute, productAmount: $0.productAmount)
        }
        copy.pauses = nil
        copy.revisions = nil
        let today = calendar.startOfDay(for: date)
        if (anchorDay?.date(in: calendar) ?? .distantPast) < today {
            var firstDay = today
            if let intervalDays, (2...365).contains(intervalDays),
               let offset = offsetFromAnchor(on: today, calendar: calendar) {
                let remaining = (intervalDays - offset % intervalDays) % intervalDays
                firstDay = calendar.date(byAdding: .day, value: remaining, to: today) ?? today
            }
            copy.anchorDay = AnchorDay(firstDay, calendar: calendar)
        }
        if isPastEnd(on: copy.anchorDay?.date(in: calendar) ?? today, calendar: calendar) { copy.endDay = nil }
        return copy
    }

    func amount(for slot: RoutineOccurrenceSlot) -> Double? {
        let timeID = slot.timeID
        return additionalTimes?.first { $0.id == timeID }?.productAmount ?? productAmount
    }

    func amount(for slot: RoutineOccurrenceSlot, calendar: Calendar) -> Double? {
        let effective = revision(on: slot.scheduledAt, calendar: calendar)?.schedule ?? self
        return effective.amount(for: slot)
    }

    func intervalCanReachSelectedDays(calendar: Calendar) -> Bool {
        guard let intervalDays, intervalDays.isMultiple(of: 7), let weekdays,
              let anchor = anchorDay?.date(in: calendar) else { return true }
        return weekdays.contains(calendar.component(.weekday, from: anchor))
    }

    func revision(on day: Date, calendar: Calendar) -> Revision? {
        revisions?.first(where: { revision in
            revision.effectiveBefore.date(in: calendar).map { calendar.startOfDay(for: day) < $0 } == true
        })
    }

    mutating func preserveSchedule(_ previous: Self, productChanged: Bool, at date: Date, calendar: Calendar) {
        var previous = previous
        var current = self
        var history = previous.revisions ?? []
        previous.revisions = nil
        current.revisions = nil
        // A rename or reminder toggle does not change when or how past occurrences were logged.
        current.name = previous.name
        current.reminds = previous.reminds
        if productChanged {
            for index in history.indices { history[index].preservesProduct = false }
        }
        if previous != current || productChanged {
            let boundary = AnchorDay(date, calendar: calendar)
            if history.last?.effectiveBefore.date(in: calendar).map({ $0 < calendar.startOfDay(for: date) }) != false {
                history.append(.init(effectiveBefore: boundary, schedule: previous, preservesProduct: !productChanged))
            }
        }
        revisions = history.isEmpty ? nil : history
    }

    func reminderDays() -> [Int?] {
        if let weekdays { return weekdays.sorted().map(Optional.some) }
        return [nil]
    }

    func slot(on day: Date, calendar: Calendar, time: ClockTime? = nil) -> RoutineOccurrenceSlot? {
        let time = time ?? ClockTime(id: id, hour: hour, minute: minute)
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        guard !isAsNeeded, !isPastEnd(on: day, calendar: calendar),
              weekdays == nil || components.weekday.map({ weekdays?.contains($0) == true }) == true,
              let year = components.year, let month = components.month, let dayNumber = components.day,
              let scheduledAt = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
              calendar.isDate(day, inSameDayAs: scheduledAt),
              pauses?.contains(where: { $0.contains(scheduledAt) }) != true
        else { return nil }
        if let monthlyDay, let month = calendar.range(of: .day, in: .month, for: day),
           dayNumber != min(monthlyDay, month.count) { return nil }
        if anchorDay != nil {
            guard let offset = offsetFromAnchor(on: day, calendar: calendar), offset >= 0 else { return nil }
            if let intervalDays, !(2...365).contains(intervalDays) || !offset.isMultiple(of: intervalDays) { return nil }
        }
        // A civil day and stable time ID identify a slot, even after editing its clock time.
        // Keep the original key for a routine's first time so older logs stay linked.
        let dayKey = "\(id.uuidString).\(year)-\(month)-\(dayNumber)"
        let key = time.id == id ? dayKey : dayKey + "." + time.id.uuidString
        return RoutineOccurrenceSlot(id: key, scheduleID: id, scheduledAt: scheduledAt)
    }

    private func isPastEnd(on date: Date, calendar: Calendar) -> Bool {
        endDay?.date(in: calendar).map { calendar.startOfDay(for: date) > $0 } ?? false
    }

    func slots(on day: Date, calendar: Calendar) -> [RoutineOccurrenceSlot] {
        let schedule = revision(on: day, calendar: calendar)?.schedule ?? self
        return schedule.times.sorted { $0.minuteOfDay < $1.minuteOfDay }
            .compactMap { schedule.slot(on: day, calendar: calendar, time: $0) }
    }

    func nextSlots(after date: Date, calendar: Calendar, limit: Int) -> [RoutineOccurrenceSlot] {
        guard isAvailable(forRemindersAfter: date, calendar: calendar), limit > 0 else { return [] }
        let day = calendar.startOfDay(for: date)
        let firstDay = max(day, anchorDay?.date(in: calendar) ?? day)
        let component: Calendar.Component
        let start: Date
        let stride: Int
        let attempts: Int
        if let intervalDays {
            guard (2...365).contains(intervalDays), let anchor = anchorDay?.date(in: calendar),
                  let offset = offsetFromAnchor(on: firstDay, calendar: calendar) else { return [] }
            component = .day
            guard let intervalStart = calendar.date(byAdding: .day, value: (offset / intervalDays) * intervalDays, to: anchor)
            else { return [] }
            start = intervalStart
            stride = intervalDays
            attempts = weekdays == nil ? limit + 1 : (limit + 1) * 7
        } else if monthlyDay != nil {
            component = .month
            start = calendar.dateInterval(of: .month, for: firstDay)?.start ?? firstDay
            stride = 1
            attempts = limit + 1
        } else {
            component = .day
            start = firstDay
            stride = 1
            attempts = weekdays == nil ? limit + 1 : (limit + 1) * 7
        }
        let times = times.sorted { $0.minuteOfDay < $1.minuteOfDay }
        var result: [RoutineOccurrenceSlot] = []
        for index in 0..<attempts {
            guard var candidate = calendar.date(byAdding: component, value: index * stride, to: start) else { break }
            if let monthlyDay, let month = calendar.range(of: .day, in: .month, for: candidate),
               let monthlyDate = calendar.date(byAdding: .day, value: min(monthlyDay, month.count) - 1, to: candidate) {
                candidate = monthlyDate
            }
            if isPastEnd(on: candidate, calendar: calendar) { break }
            for time in times {
                if let slot = slot(on: candidate, calendar: calendar, time: time), slot.scheduledAt > date {
                    result.append(slot)
                    if result.count == limit { return result }
                }
            }
        }
        return result
    }

    private func offsetFromAnchor(on date: Date, calendar: Calendar) -> Int? {
        guard let anchor = anchorDay?.date(in: calendar) else { return nil }
        return calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day
    }
}

struct RoutineNotificationResponse: Sendable {
    static let category = "RoutineReminder"
    enum Action: String, Sendable {
        case log = "RoutineLog"
        case skip = "RoutineSkip"
        case snooze = "RoutineSnooze"
    }

    let action: Action
    let scheduleID: UUID
    let timeID: UUID
    let hour: Int
    let minute: Int
    let occurredAt: Date?
    let deliveredAt: Date

    init?(_ response: UNNotificationResponse) {
        let notification = response.notification
        let content = notification.request.content
        guard content.categoryIdentifier == Self.category,
              let action = (response.actionIdentifier == UNNotificationDefaultActionIdentifier
                            ? .log : Action(rawValue: response.actionIdentifier)),
              let schedule = content.userInfo["schedule"] as? String, let scheduleID = UUID(uuidString: schedule),
              let time = content.userInfo["time"] as? String, let timeID = UUID(uuidString: time),
              let hour = content.userInfo["hour"] as? Int, let minute = content.userInfo["minute"] as? Int
        else { return nil }
        self.action = action
        self.scheduleID = scheduleID
        self.timeID = timeID
        self.hour = hour
        self.minute = minute
        occurredAt = (content.userInfo["occurrenceDate"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        deliveredAt = notification.date
    }

    static var notificationCategory: UNNotificationCategory {
        let actions = [
            UNNotificationAction(identifier: Action.log.rawValue, title: String(localized: "Log"),
                                 options: [.foreground, .authenticationRequired]),
            UNNotificationAction(identifier: Action.snooze.rawValue, title: String(localized: "Snooze 15 Minutes"),
                                 options: [.authenticationRequired]),
            UNNotificationAction(identifier: Action.skip.rawValue, title: String(localized: "Skip"),
                                 options: [.authenticationRequired]),
        ]
        return UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: [])
    }
}

extension RoutineRecord {
    var hasAvailableProduct: Bool {
        switch schedule?.productKind {
        case .customUnit: customUnit.map { !$0.isArchived } == true
        case .formulation: formulation.map { !$0.componentsSorted.isEmpty } == true
        case nil: true
        }
    }

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
        experience(isUnconfirmed: false)
    }

    var unconfirmedExperience: Experience? {
        experience(isUnconfirmed: true)
    }

    private func experience(isUnconfirmed: Bool) -> Experience? {
        let ingestions = ingestions?.allObjects as? [Ingestion] ?? []
        return ingestions.filter { $0.isUnconfirmed == isUnconfirmed }
            .sorted { $0.timeUnwrapped < $1.timeUnwrapped }.compactMap(\.experience).first
    }
}

@MainActor
final class RoutineSchedules: ObservableObject {
    static let shared = RoutineSchedules()
    nonisolated static let testReminderID = "freaklog.routine-preview"

    private static let reminderPrefix = "freaklog.routine."
    @Published private(set) var schedules: [RoutineSchedule] = []
    @Published private(set) var isUpdating = false
    @Published private(set) var loadError: String?
    @Published private(set) var reminderError: String?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published var notificationReview: RoutineOccurrenceSlot?
    @Published var notificationError: String?

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
        guard schedule.isValid, schedule.intervalCanReachSelectedDays(calendar: Self.calendar)
        else { throw StorageError.invalidSchedule }
        isUpdating = true
        defer { isUpdating = false }

        let context = try PersistenceController.shared.journalEditContext()
        let original = try Self.record(for: schedule.id, in: context)
        let wasReminding = original?.schedule?.reminds == true
        var schedule = schedule
        if let original, let previous = original.schedule {
            let previousProduct = original.customUnit?.objectID ?? original.formulation?.objectID
            let productChanged = previousProduct != productID || previous.productKind != schedule.productKind
            schedule.preserveSchedule(previous, productChanged: productChanged, at: .now, calendar: Self.calendar)
        }
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

    func sendTestReminder() async throws {
        guard !isUpdating else { throw StorageError.busy }
        isUpdating = true
        defer { isUpdating = false }

        let center = UNUserNotificationCenter.current()
        authorization = await center.notificationSettings().authorizationStatus
        if authorization == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            authorization = await center.notificationSettings().authorizationStatus
        }
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        else { throw StorageError.notificationsUnavailable }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Routine Reminder Preview")
        content.body = String(localized: "This is a test reminder.")
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: Self.testReminderID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        ))
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
            guard !occurrence.isSkipped else { throw StorageError.skipped }
            if let until = occurrence.snoozedUntil, until > .now { return }
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

    func handleNotification(_ response: RoutineNotificationResponse) async {
        // Foregrounding may have started a refresh before the notification delegate runs.
        for _ in 0..<20 where isUpdating || PersistenceController.isJournalOperationInProgress {
            try? await Task.sleep(for: .milliseconds(100))
        }
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let calendar = Self.calendar
            let date = response.occurredAt ?? response.deliveredAt
            guard !isUpdating,
                  let schedule = try Self.record(for: response.scheduleID, in: context)?.schedule
            else { throw StorageError.missingRoutine }
            let effective = schedule.revision(on: date, calendar: calendar)?.schedule ?? schedule
            guard let clock = effective.times.first(where: { $0.id == response.timeID }),
                  clock.hour == response.hour, clock.minute == response.minute,
                  let slot = effective.slot(on: date, calendar: calendar, time: clock),
                  response.deliveredAt >= slot.scheduledAt.addingTimeInterval(-60),
                  response.occurredAt.map({ $0 == slot.scheduledAt }) != false
            else { throw StorageError.missingRoutine }

            switch response.action {
            case .log:
                let occurrence = try Self.occurrence(for: slot, in: context)
                guard occurrence.ingestions?.count ?? 0 == 0 else { throw StorageError.alreadyLogged }
                guard !occurrence.isSkipped else { throw StorageError.skipped }
                notificationReview = slot
            case .skip:
                try await setDisposition(.skip, for: slot)
            case .snooze:
                try await setDisposition(.snooze, for: slot)
            }
        } catch {
            notificationError = error.localizedDescription
        }
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

    static func stageLog(
        for slot: RoutineOccurrenceSlot, in context: NSManagedObjectContext, calendar: Calendar
    ) throws -> RoutineOccurrence? {
        let occurrence = try occurrence(for: slot, in: context)
        // Saving happens synchronously on the main actor, in the same transaction as these links.
        guard occurrence.ingestions?.count ?? 0 == 0 else { return nil }
        guard !occurrence.isSkipped else { throw StorageError.skipped }
        guard let routine = occurrence.routine, let schedule = routine.schedule else { throw StorageError.missingRoutine }
        guard routine.hasAvailableProduct else { throw StorageError.missingProduct }
        let revision = schedule.revision(on: slot.scheduledAt, calendar: calendar)
        guard revision?.preservesProduct != false else { throw StorageError.missingProduct }
        let effective = revision?.schedule ?? schedule
        if slot.isManual {
            guard effective.canLogAsNeeded(at: slot.scheduledAt, calendar: calendar) else { throw StorageError.missingRoutine }
        } else {
            guard let time = effective.times.first(where: { $0.id == (slot.timeID ?? slot.scheduleID) }),
                  effective.slot(on: slot.scheduledAt, calendar: calendar, time: time) == slot
            else { throw StorageError.missingRoutine }
        }
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
            if let old, let new, let oldContent = existing[request.identifier]?.content,
               old.dateComponents == new.dateComponents, old.repeats == new.repeats,
               oldContent.categoryIdentifier == request.content.categoryIdentifier,
               NSDictionary(dictionary: oldContent.userInfo).isEqual(to: request.content.userInfo) { continue }
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
        var reminders: [UNNotificationRequest] = records.compactMap { occurrence in
            guard let routine = occurrence.routine, routine.hasAvailableProduct,
                  let schedule = routine.schedule, !schedule.isPaused,
                  let id = occurrence.key, let scheduledAt = occurrence.scheduledAt,
                  let alert = occurrence.snoozedUntil, alert > now,
                  !occurrence.isSkipped, (occurrence.ingestions?.count ?? 0) == 0 else { return nil }
            let slot = RoutineOccurrenceSlot(id: id, scheduleID: schedule.id, scheduledAt: scheduledAt)
            let revision = schedule.revision(on: scheduledAt, calendar: calendar)
            let effective = revision?.schedule ?? schedule
            guard revision?.preservesProduct != false,
                  let clock = effective.times.first(where: { $0.id == (slot.timeID ?? schedule.id) }),
                  effective.slot(on: scheduledAt, calendar: calendar, time: clock)?.scheduledAt == scheduledAt
            else { return nil }
            return reminder(id: id + ".snoozed", schedule: schedule, time: clock, slot: slot,
                            date: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert))
        }
        let availableSchedules = try context.fetch(RoutineRecord.fetchRequest()).compactMap { record in
            record.hasAvailableProduct ? record.schedule : nil
        }
        for schedule in availableSchedules where schedule.reminds && schedule.isAvailable(forRemindersAfter: now, calendar: calendar) {
            func add(_ slot: RoutineOccurrenceSlot, time: RoutineSchedule.ClockTime) {
                guard !suppressed.contains(slot.id) else { return }
                let date = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot.scheduledAt)
                reminders.append(reminder(id: slot.id, schedule: schedule, time: time, slot: slot, date: date))
            }
            if schedule.intervalDays != nil || schedule.monthlyDay != nil {
                for slot in schedule.nextSlots(after: now, calendar: calendar, limit: 24) {
                    if let time = schedule.times.first(where: { $0.id == (slot.timeID ?? schedule.id) }) {
                        add(slot, time: time)
                    }
                }
                continue
            }
            for time in schedule.times {
                for weekday in schedule.reminderDays() {
                    let date = DateComponents(hour: time.hour, minute: time.minute, weekday: weekday)
                    let firstDay = schedule.anchorDay?.date(in: calendar) ?? now
                    var cursor = max(now, firstDay.addingTimeInterval(-1))
                    if schedule.endDay == nil, cursor == now,
                       let next = calendar.nextDate(after: cursor, matching: date, matchingPolicy: .nextTime),
                       let slot = schedule.slot(on: next, calendar: calendar, time: time),
                       !suppressed.contains(slot.id) {
                        let id = time.id.uuidString + "." + (weekday.map(String.init) ?? "daily")
                        reminders.append(reminder(id: id, schedule: schedule, time: time, date: date))
                        continue
                    }
                    // Calendar repeats cannot omit a date or obey an end date.
                    for _ in 0..<12 {
                        guard let next = calendar.nextDate(after: cursor, matching: date, matchingPolicy: .nextTime),
                              let slot = schedule.slot(on: next, calendar: calendar, time: time) else { break }
                        add(slot, time: time)
                        cursor = next
                    }
                }
            }
        }
        let available = max(0, 64 - existingOtherRequests)
        let upcoming = reminders.compactMap { reminder in
            (reminder.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate().map { ($0, reminder) }
        }.sorted { ($0.0, $0.1.identifier) < ($1.0, $1.1.identifier) }
        return upcoming.prefix(available).map { $0.1 }
    }

    private func reminder(
        id: String, schedule: RoutineSchedule, time: RoutineSchedule.ClockTime,
        slot: RoutineOccurrenceSlot? = nil, date: DateComponents
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Routine Reminder")
        content.body = String(localized: "A scheduled routine is due.")
        content.sound = .default
        content.categoryIdentifier = RoutineNotificationResponse.category
        content.userInfo = [
            "schedule": schedule.id.uuidString, "time": time.id.uuidString,
            "hour": time.hour, "minute": time.minute,
        ]
        if let slot { content.userInfo["occurrenceDate"] = slot.scheduledAt.timeIntervalSinceReferenceDate }
        return UNNotificationRequest(
            identifier: Self.reminderPrefix + id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: slot == nil))
    }

    enum StorageError: LocalizedError {
        case busy, unreadable, invalidSchedule, missingRoutine, missingProduct, alreadyLogged, skipped, notificationsUnavailable

        var errorDescription: String? {
            switch self {
            case .busy: "Routines are updating. Try again in a moment."
            case .unreadable: "Saved routines couldn’t be read."
            case .invalidSchedule: "Enter a name, select at least one day, and check the product amount."
            case .missingRoutine: "This routine is no longer available."
            case .missingProduct: "Choose an available product for this routine."
            case .alreadyLogged: "This occurrence has already been logged."
            case .skipped: "Reopen this occurrence before logging it."
            case .notificationsUnavailable: "Allow notifications for FreakLog in Settings to receive a test reminder."
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
