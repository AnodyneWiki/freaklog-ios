import CoreData
import CryptoKit
import Foundation
import WidgetKit

extension RoutineRecord {
    func ingestionArguments(amount: Double) -> [FinishIngestionScreenArguments] {
        guard amount.isFinite, amount > 0 else { return [] }
        switch schedule?.productKind {
        case .customUnit:
            guard let customUnit, !customUnit.isArchived else { return [] }
            return [FinishIngestionScreenArguments(
                substanceName: customUnit.substanceNameUnwrapped,
                administrationRoute: customUnit.administrationRouteUnwrapped,
                dose: amount,
                units: customUnit.originalUnitUnwrapped,
                isEstimate: false,
                estimatedDoseStandardDeviation: nil,
                customUnit: customUnit)]
        case .formulation:
            return formulation?.ingestionArguments(amount: amount) ?? []
        case nil:
            return []
        }
    }
}

@MainActor
enum RoutineQuickLogging {
    private static var pendingRefresh: Task<Void, Never>?

    static func observeChanges() {
        let center = NotificationCenter.default
        for name in [
            NSManagedObjectContext.didSaveObjectIDsNotification,
            NSManagedObjectContext.didMergeChangesObjectIDsNotification,
            UserDefaults.didChangeNotification,
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    refreshSoon()
                }
            }
        }
        refresh()
    }

    private static func refreshSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { refresh() }
        }
    }

    static func refresh() {
        let snapshot = currentSnapshot()
        if snapshot != RoutineQuickSnapshot.read() {
            do {
                if try snapshot.write() {
                    WidgetCenter.shared.reloadTimelines(ofKind: "NextRoutine")
                }
            } catch {
                print("Couldn’t update the next routine widget: \(error)")
            }
        }
        PhoneWatchSession.shared.sendRoutineUpdate(snapshot)
    }

    static func currentSnapshot(defaults: UserDefaults = .standard) -> RoutineQuickSnapshot {
        guard defaults.bool(forKey: PersistenceController.isEyeOpenKey2) else { return .empty }
        guard !defaults.bool(forKey: PersistenceController.hasToUnlockAppKey) else {
            return RoutineQuickSnapshot(previews: [], phoneLocked: true)
        }
        return (try? snapshot(in: .shared, at: .now, calendar: RoutineSchedules.calendar)) ?? .empty
    }

    static func markTaken(_ request: RoutineTakenRequest, defaults: UserDefaults = .standard) throws {
        guard defaults.bool(forKey: PersistenceController.isEyeOpenKey2),
              !defaults.bool(forKey: PersistenceController.hasToUnlockAppKey) else {
            throw MarkRoutineTakenError.openJournal
        }
        let persistence = PersistenceController.shared
        let ids = try save(request, in: persistence, now: .now, calendar: RoutineSchedules.calendar)
        let ingestions = ids.compactMap { try? persistence.viewContext.existingObject(with: $0) as? Ingestion }
        IngestionSaving.didSave(ingestions, newIngestions: ingestions)
        refresh()
    }

    static func snapshot(
        in persistence: PersistenceController, at date: Date, calendar: Calendar
    ) throws -> RoutineQuickSnapshot {
        let context = try persistence.journalEditContext()
        let records = try context.fetch(RoutineRecord.fetchRequest())
        let today = calendar.startOfDay(for: date)
        let candidates = records.flatMap { record -> [(RoutineOccurrenceSlot, RoutineRecord)] in
            guard let schedule = record.schedule, schedule.isAvailable(forRemindersAfter: date, calendar: calendar)
            else { return [] }
            let slots = schedule.nextSlots(after: today.addingTimeInterval(-1), calendar: calendar, limit: 32)
            return slots.map { ($0, record) }
        }
        guard !candidates.isEmpty else { return .empty }
        let occurrenceRequest = RoutineOccurrence.fetchRequest()
        occurrenceRequest.predicate = NSPredicate(format: "scheduledAt >= %@", today as NSDate)
        let completed = try context.fetch(occurrenceRequest).filter {
            $0.isSkipped || ($0.ingestions?.count ?? 0) > 0 || ($0.snoozedUntil ?? .distantPast) > date
        }
        let excluded = Set(completed.compactMap(\.key))
        let ordered = candidates.sorted { ($0.0.scheduledAt, $0.0.id) < ($1.0.scheduledAt, $1.0.id) }
        // At a time shared by several routines the user chooses the specific routine in the app.
        let available = ordered.filter { !excluded.contains($0.0.id) }
        let groups = Dictionary(grouping: available) { $0.0.scheduledAt }
        var previews: [RoutineQuickSnapshot.Preview] = []
        for (slot, record) in available {
            guard try !hasReceipt(for: slot, in: context),
                  let day = calendar.dateInterval(of: .day, for: slot.scheduledAt) else { continue }
            let action = groups[slot.scheduledAt]?.count == 1 ? try? action(for: slot, record: record) : nil
            previews.append(.init(scheduledAt: slot.scheduledAt, dayStart: day.start, dayEnd: day.end, action: action))
            if previews.count == 10 { break }
        }
        return RoutineQuickSnapshot(previews: previews, phoneLocked: false)
    }

    @discardableResult
    static func save(
        _ request: RoutineTakenRequest, in persistence: PersistenceController, now: Date, calendar: Calendar
    ) throws -> [NSManagedObjectID] {
        let slot = request.action.slot
        let context = try persistence.journalEditContext()
        return try PersistenceController.withJournalStoreWrite {
            guard try !hasReceipt(for: slot, in: context) else { return [] }
            guard request.recordedAt.timeIntervalSinceReferenceDate.isFinite,
                  slot.scheduledAt.timeIntervalSinceReferenceDate.isFinite,
                  request.recordedAt >= now.addingTimeInterval(-7 * 86_400),
                  request.recordedAt <= now.addingTimeInterval(60),
                  calendar.isDate(request.recordedAt, inSameDayAs: slot.scheduledAt),
                  let record = try RoutineSchedules.record(for: slot.scheduleID, in: context),
                  let schedule = record.schedule, !schedule.isPaused,
                  schedule.revision(on: slot.scheduledAt, calendar: calendar) == nil,
                  let clock = schedule.times.first(where: { $0.id == (slot.timeID ?? slot.scheduleID) }),
                  schedule.slot(on: slot.scheduledAt, calendar: calendar, time: clock) == slot,
                  let amount = schedule.amount(for: slot),
                  request.action == (try? action(for: slot, record: record))
            else { throw MarkRoutineTakenError.routineChanged }
            guard let occurrence = try RoutineSchedules.stageLog(for: slot, in: context) else { return [] }

            let arguments = record.ingestionArguments(amount: amount)
            var companions = try context.fetch(PersistenceController.substanceCompanionsRequest())
            let experience = Experience.create(at: request.recordedAt, title: "", in: context)
            let ingestions = arguments.map { argument in
                let ingestion = Ingestion(context: context)
                ingestion.identifier = UUID()
                ingestion.time = request.recordedAt
                ingestion.creationDate = now
                ingestion.substanceName = argument.substanceName
                ingestion.administrationRoute = argument.administrationRoute.rawValue
                ingestion.dose = argument.dose ?? 0
                ingestion.units = argument.units
                ingestion.isEstimate = argument.isEstimate
                ingestion.estimatedDoseStandardDeviation = argument.estimatedDoseStandardDeviation ?? 0
                ingestion.isHiddenInTimeline = argument.isHiddenInTimeline
                ingestion.customUnit = argument.customUnit
                ingestion.formulation = argument.formulation
                ingestion.formulationAmount = argument.formulationAmount ?? 0
                ingestion.routineOccurrence = occurrence
                ingestion.experience = experience
                if let companion = companions.first(where: { $0.substanceName == argument.substanceName }) {
                    ingestion.substanceCompanion = companion
                } else {
                    let companion = SubstanceCompanion(context: context)
                    companion.substanceName = argument.substanceName
                    companion.colorAsText = SubstanceColor.suggested(avoiding: companions.map(\.color)).rawValue
                    ingestion.substanceCompanion = companion
                    companions.append(companion)
                }
                ingestion.color = ingestion.substanceCompanion?.color.rawValue
                return ingestion
            }
            let receipt = WatchLogReceipt(context: context)
            receipt.requestID = slot.receiptID
            receipt.record = Data(slot.id.utf8)
            try PersistenceController.saveJournalChanges(in: context)
            return ingestions.map(\.objectID)
        }
    }

    private static func hasReceipt(for slot: RoutineOccurrenceSlot, in context: NSManagedObjectContext) throws -> Bool {
        let request = WatchLogReceipt.fetchRequest()
        request.predicate = NSPredicate(format: "requestID == %@", slot.receiptID as CVarArg)
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    private static func action(for slot: RoutineOccurrenceSlot, record: RoutineRecord) throws -> RoutineQuickAction? {
        guard let amount = record.schedule?.amount(for: slot) else { return nil }
        let arguments = record.ingestionArguments(amount: amount)
        guard !arguments.isEmpty,
              arguments.allSatisfy({ argument in
                  !argument.substanceName.isEmpty
                      && [argument.dose, argument.estimatedDoseStandardDeviation].compactMap { $0 }.allSatisfy {
                          $0.isFinite && $0 >= 0
                      }
              }) else { return nil }
        let product = arguments.map(LoggingDetails.init)
        let data = try WatchQuickLog.encode(product)
        return RoutineQuickAction(slot: slot, revision: Data(SHA256.hash(data: data)))
    }

    private struct LoggingDetails: Encodable {
        let product: URL?
        let name: String
        let route: String
        let units: String?
        let dose: Double?
        let deviation: Double?
        let isEstimate: Bool
        let isHidden: Bool
        let productName: String?
        let customUnitLabel: String?
        let customUnitDose: Double?
        let customUnitDeviation: Double?
        let customUnitIsEstimate: Bool?
        let formulationAmount: Double?

        init(_ argument: FinishIngestionScreenArguments) {
            product = (argument.customUnit?.objectID ?? argument.formulation?.objectID)?.uriRepresentation()
            productName = argument.customUnit?.nameUnwrapped ?? argument.formulation?.nameUnwrapped
            name = argument.substanceName
            route = argument.administrationRoute.rawValue
            units = argument.units
            dose = argument.dose
            deviation = argument.estimatedDoseStandardDeviation
            isEstimate = argument.isEstimate
            isHidden = argument.isHiddenInTimeline
            customUnitLabel = argument.customUnit?.unitUnwrapped
            customUnitDose = argument.customUnit?.doseUnwrapped
            customUnitDeviation = argument.customUnit?.estimatedDoseStandardDeviationUnwrapped
            customUnitIsEstimate = argument.customUnit?.isEstimate
            formulationAmount = argument.formulationAmount
        }
    }
}
