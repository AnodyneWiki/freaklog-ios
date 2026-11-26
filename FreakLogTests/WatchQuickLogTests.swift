import CoreData
import XCTest
@testable import FreakLog

final class WatchQuickLogTests: XCTestCase {
  @MainActor
  func testTakenFromWatchAndWidgetUsesOneOccurrenceAcrossRetries() throws {
    let (persistence, calendar, now, record) = try makeRoutine()
    let snapshot = try RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar)
    let action = try XCTUnwrap(snapshot.next(at: now)?.action)
    let widgetRequest = RoutineTakenRequest(action: action, recordedAt: now)
    let watchRequest = RoutineTakenRequest(action: action, recordedAt: now.addingTimeInterval(60))
    let message = try WatchRequest.routineTaken(watchRequest).message()
    XCTAssertEqual(WatchRequest(kind: .routineTaken, payload: message[WatchQuickLog.routineTakenKey]), .routineTaken(watchRequest))
    XCTAssertEqual(widgetRequest.id, watchRequest.id)

    let ids = try RoutineQuickLogging.save(widgetRequest, in: persistence, now: now, calendar: calendar)
    XCTAssertEqual(ids.count, 1)
    let context = persistence.viewContext
    let saved = try XCTUnwrap(context.existingObject(with: XCTUnwrap(ids.first)) as? Ingestion)
    XCTAssertEqual(saved.routineOccurrence?.key, action.slot.id)
    XCTAssertEqual(saved.routineOccurrence?.routine, record)
    XCTAssertEqual(saved.customUnit, record.customUnit)
    XCTAssertEqual(saved.dose, 1)
    let retry = try RoutineQuickLogging.save(watchRequest, in: persistence, now: watchRequest.recordedAt, calendar: calendar)
    XCTAssertTrue(retry.isEmpty)
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 1)

    // A delayed Watch retry cannot recreate a log the user has intentionally deleted.
    context.delete(saved)
    try context.save()
    XCTAssertTrue(try RoutineQuickLogging.save(watchRequest, in: persistence, now: watchRequest.recordedAt, calendar: calendar).isEmpty)
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 0)
  }

  @MainActor
  func testTakenRejectsAChangedProductWithoutWritingAnything() throws {
    let (persistence, calendar, now, record) = try makeRoutine()
    let snapshot = try RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar)
    let action = try XCTUnwrap(snapshot.next(at: now)?.action)
    record.customUnit?.dose = 50
    try persistence.viewContext.save()

    let request = RoutineTakenRequest(action: action, recordedAt: now)
    XCTAssertThrowsError(try RoutineQuickLogging.save(request, in: persistence, now: now, calendar: calendar))
    XCTAssertEqual(try persistence.viewContext.count(for: Ingestion.fetchRequest()), 0)
    XCTAssertEqual(try persistence.viewContext.count(for: RoutineOccurrence.fetchRequest()), 0)
    XCTAssertEqual(try persistence.viewContext.count(for: WatchLogReceipt.fetchRequest()), 0)
  }

  @MainActor
  func testDeletedRoutineLogDoesNotBlockAnotherRoutineAtSameTime() throws {
    let (persistence, calendar, now, first) = try makeRoutine()
    let originalAction = try XCTUnwrap(RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar).next(at: now)?.action)
    let ids = try RoutineQuickLogging.save(.init(action: originalAction, recordedAt: now),
                                           in: persistence, now: now, calendar: calendar)
    let context = try persistence.journalEditContext()
    for id in ids { context.delete(try context.existingObject(with: id)) }

    let second = RoutineRecord(context: context)
    let schedule = RoutineSchedule(name: "Another routine", hour: 9, minute: 0, productKind: .customUnit, productAmount: 2)
    second.id = schedule.id
    second.scheduleData = try JSONEncoder().encode(schedule)
    second.customUnit = try context.existingObject(with: XCTUnwrap(first.customUnit?.objectID)) as? CustomUnit
    try context.save()

    let preview = try RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar).next(at: now)
    XCTAssertEqual(preview?.action?.slot.scheduleID, schedule.id)
  }

  @MainActor
  func testTakenUsesHistoricalAmountWhenScheduleChangesAfterRecording() throws {
    let (persistence, calendar, now, record) = try makeRoutine()
    let action = try XCTUnwrap(RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar).next(at: now)?.action)
    let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
    let previous = try XCTUnwrap(record.schedule)
    var schedule = previous
    schedule.productAmount = 2
    schedule.preserveSchedule(previous, productChanged: false, at: tomorrow, calendar: calendar)
    record.scheduleData = try JSONEncoder().encode(schedule)
    try persistence.viewContext.save()

    let ids = try RoutineQuickLogging.save(.init(action: action, recordedAt: now),
                                          in: persistence, now: tomorrow, calendar: calendar)
    let context = try persistence.journalEditContext()
    let saved = try context.existingObject(with: XCTUnwrap(ids.first)) as? Ingestion
    XCTAssertEqual(saved?.dose, previous.productAmount)
    XCTAssertEqual(saved?.time, now)
  }

  @MainActor
  func testSnoozedPreviewReappearsFromTheSameSnapshot() throws {
    let (persistence, calendar, now, _) = try makeRoutine()
    let action = try XCTUnwrap(RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar).next(at: now)?.action)
    let snoozedUntil = now.addingTimeInterval(900)
    let context = try persistence.journalEditContext()
    let occurrence = try RoutineSchedules.occurrence(for: action.slot, in: context)
    occurrence.snoozedUntil = snoozedUntil
    try context.save()

    let snapshot = try RoutineQuickLogging.snapshot(in: persistence, at: now, calendar: calendar)
    XCTAssertNotEqual(snapshot.next(at: now)?.scheduledAt, now)
    XCTAssertEqual(snapshot.next(at: snoozedUntil)?.action, action)
  }

  @MainActor
  private func makeRoutine() throws -> (PersistenceController, Calendar, Date, RoutineRecord) {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9)))
    let schedule = RoutineSchedule(
      name: "Routine", hour: 9, minute: 0, productKind: .customUnit, productAmount: 1)
    let record = RoutineRecord(context: context)
    record.id = schedule.id
    record.scheduleData = try JSONEncoder().encode(schedule)
    let unit = CustomUnit(context: context)
    unit.name = "Saved Product"
    unit.substanceName = "Caffeine"
    unit.administrationRoute = "oral"
    unit.unit = "Capsule"
    unit.originalUnit = "mg"
    unit.dose = 25
    record.customUnit = unit
    try context.save()
    return (persistence, calendar, date, record)
  }

  func testDoseStepTakesAboutTwentyTurns() {
    XCTAssertEqual(WatchQuickLog.doseStep(around: 100), 5)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 250), 10)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 10), 0.5, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 1.5), 0.1, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 3), 0.2, accuracy: 1e-9)
    XCTAssertEqual(WatchQuickLog.doseStep(around: 0), 1)
  }

  func testCrownStartsAtTheLatestKnownDose() {
    let doses = [
      WatchDose(amount: nil, isEstimate: false, standardDeviation: nil),
      WatchDose(amount: 80, isEstimate: false, standardDeviation: nil),
      WatchDose(amount: 120, isEstimate: false, standardDeviation: nil),
    ]
    XCTAssertEqual(suggestion(doses: doses).typicalDose, 80)
    XCTAssertEqual(suggestion(doses: []).typicalDose, 0)
  }

  func testCustomUnitsMoveByHalfUnits() {
    let doses = [WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)]
    XCTAssertEqual(suggestion(customUnit: pill, doses: doses).doseStep, 0.5)
  }

  func testDescribesDoses() {
    let suggestion = suggestion(doses: [])
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: false, standardDeviation: nil)), "100 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: true, standardDeviation: nil)), "~100 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: 100, isEstimate: true, standardDeviation: 10)), "100±10 mg")
    XCTAssertEqual(suggestion.description(of: WatchDose(amount: nil, isEstimate: false, standardDeviation: nil)), "Unknown dose")
    XCTAssertNil(suggestion.calculatedDescription(of: WatchDose(amount: 100, isEstimate: false, standardDeviation: nil)))
  }

  func testDescribesCustomUnitDoses() {
    let suggestion = suggestion(customUnit: pill, doses: [])
    let one = WatchDose(amount: 1, isEstimate: false, standardDeviation: nil)
    let two = WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)
    XCTAssertEqual(suggestion.description(of: one), "1 pill")
    XCTAssertEqual(suggestion.description(of: two), "2 pills")
    XCTAssertEqual(suggestion.calculatedDescription(of: two), "240 mg")
    let estimated = WatchDose(amount: 1.5, isEstimate: true, standardDeviation: nil)
    XCTAssertEqual(suggestion.calculatedDescription(of: estimated), "~180 mg")
  }

  func testLogRequestRoundTrips() throws {
    let request = WatchLogRequest(
      id: UUID(),
      suggestion: suggestion(customUnit: pill, doses: [WatchDose(amount: 2, isEstimate: true, standardDeviation: 0.5)]),
      dose: WatchDose(amount: 1.5, isEstimate: false, standardDeviation: nil),
      time: Date(timeIntervalSince1970: 1_700_000_000))
    let data = try WatchQuickLog.encode(request)
    XCTAssertEqual(WatchQuickLog.decode(WatchLogRequest.self, from: data), request)
    XCTAssertNil(WatchQuickLog.decode(WatchLogRequest.self, from: "not data"))
  }

  func testDescribesFormulationAmounts() {
    let formulation = formulationSuggestion()
    let two = WatchDose(amount: 2, isEstimate: false, standardDeviation: nil)
    XCTAssertEqual(formulation.description(of: two), "2×")
    XCTAssertEqual(formulation.calculatedDescription(of: two), "200±20 mg MDMA, Unknown dose Caffeine")
    XCTAssertEqual(formulation.doseStep, 0.5)
    let component = formulation.formulation?.components.first
    XCTAssertEqual(component?.dose(for: 1.5), WatchDose(amount: 150, isEstimate: true, standardDeviation: 15))
  }

  func testFormulationRequestsKnowAllTheirIngestions() throws {
    let request = WatchLogRequest(
      id: UUID(),
      suggestion: formulationSuggestion(),
      dose: WatchDose(amount: 1, isEstimate: false, standardDeviation: nil),
      time: Date(timeIntervalSince1970: 1_700_000_000))
    let identifiers = request.ingestionIdentifiers
    XCTAssertEqual(identifiers.count, 2)
    XCTAssertEqual(identifiers.first, request.id)
    XCTAssertEqual(Set(identifiers).count, 2)
    let decoded = try XCTUnwrap(WatchQuickLog.decode(WatchLogRequest.self, from: WatchQuickLog.encode(request)))
    XCTAssertEqual(decoded, request)
    XCTAssertEqual(decoded.ingestionIdentifiers, identifiers)
    XCTAssertEqual(
      WatchLogRequest(id: request.id, suggestion: suggestion(doses: []), dose: request.dose, time: request.time)
        .ingestionIdentifiers,
      [request.id])
  }

  func testOutboxWaitsForMatchingSaveOrUndoAcknowledgement() throws {
    let file = temporaryOutboxFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var outbox = try WatchRequestOutbox(file: file)
    let request = logRequest()
    try outbox.enqueue(.log(request))

    outbox = try WatchRequestOutbox(file: file)
    XCTAssertEqual(outbox.pending[request.id], .log(request))
    XCTAssertFalse(try outbox.acknowledge(.init(id: request.id, kind: .log, status: .retry)))
    XCTAssertFalse(try outbox.acknowledge(.init(id: UUID(), kind: .log, status: .saved)))
    XCTAssertEqual(outbox.pending[request.id], .log(request))

    let undo = WatchUndoRequest(log: request)
    try outbox.enqueue(.undo(undo))
    outbox = try WatchRequestOutbox(file: file)
    XCTAssertFalse(try outbox.acknowledge(.init(id: request.id, kind: .log, status: .saved)))
    XCTAssertFalse(try outbox.acknowledge(.init(id: request.id, kind: .undo, status: .saved)))
    XCTAssertEqual(outbox.pending[request.id], .undo(undo))
    XCTAssertTrue(try outbox.acknowledge(.init(id: request.id, kind: .undo, status: .undone)))
    XCTAssertTrue(try WatchRequestOutbox(file: file).pending.isEmpty)
  }

  func testARejectedQueuedRequestRemainsVisibleAfterRelaunch() throws {
    let file = temporaryOutboxFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var outbox = try WatchRequestOutbox(file: file)
    let request = logRequest()
    try outbox.enqueue(.log(request))
    XCTAssertTrue(try outbox.acknowledge(.init(id: request.id, kind: .log, status: .rejected, message: "Unit deleted")))

    outbox = try WatchRequestOutbox(file: file)
    XCTAssertTrue(outbox.pending.isEmpty)
    XCTAssertEqual(outbox.rejections.first?.request, .log(request))
    XCTAssertEqual(outbox.rejections.first?.message, "Unit deleted")
    try outbox.dismissRejection(request.id)
    XCTAssertTrue(try WatchRequestOutbox(file: file).rejections.isEmpty)
  }

  @MainActor
  func testFormulationAndReceiptCommitTogetherAndUndoRemovesCreatedExperience() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest(formulation: true)
    let result = try WatchQuickLogging.saveLog(request, in: persistence)
    XCTAssertEqual(result.status, .saved)
    XCTAssertEqual(result.newIngestionIDs.count, 2)
    XCTAssertNotNil(result.createdExperienceID)
    XCTAssertEqual(try WatchQuickLogging.saveLog(request, in: persistence).newIngestionIDs, [])
    XCTAssertEqual(try persistence.viewContext.count(for: Ingestion.fetchRequest()), 2)

    let undo = WatchUndoRequest(log: request)
    XCTAssertEqual(Set(try WatchQuickLogging.saveUndo(undo, in: persistence)), Set(request.ingestionIdentifiers))
    XCTAssertEqual(try persistence.viewContext.count(for: Ingestion.fetchRequest()), 0)
    XCTAssertEqual(try persistence.viewContext.count(for: Experience.fetchRequest()), 0)
    XCTAssertEqual(try WatchQuickLogging.saveLog(request, in: persistence).status, .undone)
    XCTAssertEqual(try WatchQuickLogging.saveUndo(undo, in: persistence), [])
  }

  @MainActor
  func testLogLinksAnExistingFormulationThroughItsPermanentURI() throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let formulation = Formulation(context: context)
    try context.save()
    let request = WatchLogRequest(
      id: UUID(),
      suggestion: formulationSuggestion(id: formulation.objectID.uriRepresentation().absoluteString),
      dose: WatchDose(amount: 1, isEstimate: false, standardDeviation: nil),
      time: .now)

    let result = try WatchQuickLogging.saveLog(request, in: persistence)
    XCTAssertEqual(result.newIngestionIDs.count, 2)
    let ingestions = try context.fetch(Ingestion.fetchRequest())
    XCTAssertEqual(ingestions.compactMap { $0.formulation?.objectID }, [formulation.objectID, formulation.objectID])
  }

  @MainActor
  func testUndoPreservesAnExistingExperienceEvenWhenItWasEmpty() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest()
    let context = persistence.viewContext
    let experience = Experience.create(at: request.time, in: context)
    try context.save()

    let logged = try WatchQuickLogging.saveLog(request, in: persistence)
    XCTAssertNil(logged.createdExperienceID)
    XCTAssertEqual(try WatchQuickLogging.saveUndo(WatchUndoRequest(log: request), in: persistence), [request.id])
    XCTAssertEqual(try context.fetch(Experience.fetchRequest()).map(\.objectID), [experience.objectID])
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 0)
  }

  @MainActor
  func testUndoPreservesAnEditedWatchCreatedExperienceAndUnsavedChanges() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest()
    let logged = try WatchQuickLogging.saveLog(request, in: persistence)
    let id = try XCTUnwrap(logged.createdExperienceID)
    let context = persistence.viewContext
    let experience = try XCTUnwrap(context.existingObject(with: id) as? Experience)
    experience.title = "Weekend"
    let location = ExperienceLocation(context: context)
    location.name = "Home"
    experience.legacyLocation = location
    try context.save()
    experience.text = "Unsaved draft"

    XCTAssertEqual(try WatchQuickLogging.saveUndo(WatchUndoRequest(log: request), in: persistence), [request.id])
    XCTAssertEqual(try context.fetch(Experience.fetchRequest()).map(\.objectID), [id])
    XCTAssertEqual(experience.title, "Weekend")
    XCTAssertEqual(experience.legacyLocation?.name, "Home")
    XCTAssertEqual(experience.text, "Unsaved draft")
    XCTAssertTrue(context.hasChanges)
  }

  @MainActor
  func testUndoBeforeDeliveryBlocksLaterLog() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest(formulation: true)
    XCTAssertEqual(try WatchQuickLogging.saveUndo(WatchUndoRequest(log: request), in: persistence), [])
    XCTAssertEqual(try WatchQuickLogging.saveLog(request, in: persistence).status, .undone)
    XCTAssertEqual(try persistence.viewContext.count(for: Ingestion.fetchRequest()), 0)
  }

  @MainActor
  func testReceiptPreventsRecreatingAnIngestionDeletedOnPhone() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest()
    let result = try WatchQuickLogging.saveLog(request, in: persistence)
    let id = try XCTUnwrap(result.newIngestionIDs.first)
    let context = persistence.viewContext
    context.delete(try context.existingObject(with: id))
    try context.save()

    XCTAssertEqual(try WatchQuickLogging.saveLog(request, in: persistence).status, .saved)
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 0)
  }

  @MainActor
  func testMalformedFormulationDoesNotLeaveAnExperienceOrReceipt() throws {
    let persistence = PersistenceController(inMemory: true)
    let valid = logRequest(formulation: true)
    let malformed = WatchLogRequest(
      id: valid.id,
      suggestion: valid.suggestion,
      dose: WatchDose(amount: nil, isEstimate: false, standardDeviation: nil),
      time: valid.time)

    XCTAssertThrowsError(try WatchQuickLogging.saveLog(malformed, in: persistence))
    XCTAssertEqual(try persistence.viewContext.count(for: Experience.fetchRequest()), 0)
    XCTAssertEqual(try WatchQuickLogging.saveLog(valid, in: persistence).newIngestionIDs.count, 2)
  }

  @MainActor
  func testQueuedLegacyWatchUndoDeletesItsPreUpgradeLogAndCannotBeReplayed() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest()
    let context = persistence.viewContext
    let ingestion = Ingestion(context: context)
    ingestion.identifier = request.id
    try context.save()

    let wireIdentifiers = request.ingestionIdentifiers.map(\.uuidString)
    let original = try XCTUnwrap(WatchRequest(kind: .undo, payload: wireIdentifiers))
    let serialized = try WatchQuickLog.encode(original)
    let restored = try XCTUnwrap(WatchQuickLog.decode(WatchRequest.self, from: serialized))
    XCTAssertEqual(try restored.message()[WatchQuickLog.undoKey] as? [String], wireIdentifiers)
    guard case .undo(let undo) = restored else { return XCTFail("Expected an undo") }
    XCTAssertEqual(try WatchQuickLogging.saveUndo(undo, in: persistence, source: .legacyTransfer), [request.id])
    XCTAssertEqual(try persistence.journalEditContext().count(for: Ingestion.fetchRequest()), 0)
    XCTAssertEqual(try WatchQuickLogging.saveUndo(undo, in: persistence, source: .legacyTransfer), [])
    XCTAssertEqual(try WatchQuickLogging.saveLog(request, in: persistence).status, .undone)
  }

  @MainActor
  func testQueuedLegacyWatchUndoRejectsAPartialOldLog() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest(formulation: true)
    let context = persistence.viewContext
    let ingestion = Ingestion(context: context)
    ingestion.identifier = request.id
    try context.save()

    let undo = try XCTUnwrap(WatchUndoRequest(legacyIdentifiers: request.ingestionIdentifiers.map(\.uuidString)))
    XCTAssertThrowsError(try WatchQuickLogging.saveUndo(undo, in: persistence, source: .legacyTransfer))
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 1)
  }

  @MainActor
  func testConflictingLegacyUndoCannotDeleteAnUnrelatedIngestion() throws {
    let persistence = PersistenceController(inMemory: true)
    let request = logRequest()
    let context = persistence.viewContext
    let unrelated = Ingestion(context: context)
    unrelated.identifier = request.id
    try context.save()

    XCTAssertThrowsError(try WatchQuickLogging.saveUndo(WatchUndoRequest(log: request), in: persistence))
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), 1)
  }

  @MainActor
  func testLoggingInIsolatedContextLeavesUnrelatedPhoneDraftUnsaved() throws {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    _ = Experience.create(at: .now, title: "Unsaved draft", in: context)

    let result = try WatchQuickLogging.saveLog(logRequest(), in: persistence)
    XCTAssertNotNil(result.createdExperienceID)
    let storeRead = try persistence.journalEditContext()
    XCTAssertEqual(try storeRead.count(for: Experience.fetchRequest()), 1)
    XCTAssertEqual(try context.count(for: Experience.fetchRequest()), 2)
    XCTAssertTrue(context.hasChanges)
  }

  private func logRequest(formulation: Bool = false) -> WatchLogRequest {
    WatchLogRequest(
      id: UUID(), suggestion: formulation ? formulationSuggestion() : suggestion(doses: []),
      dose: WatchDose(amount: 1, isEstimate: false, standardDeviation: nil), time: .now)
  }

  private func temporaryOutboxFile() -> URL {
    URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("WatchQuickLogOutbox.json")
  }

  private func formulationSuggestion(id: String = "x-coredata://formulation") -> WatchSuggestion {
    WatchSuggestion(
      id: id,
      substanceName: "Party pill",
      displayName: "Party pill",
      route: "oral",
      color: WatchColor(red: 1, green: 0, blue: 0.5),
      units: "",
      customUnit: nil,
      doses: [WatchDose(amount: 1, isEstimate: false, standardDeviation: nil)],
      formulation: WatchFormulation(components: [
        WatchFormulationComponent(
          substanceName: "MDMA",
          displayName: "MDMA",
          route: "oral",
          units: "mg",
          dose: WatchDose(amount: 100, isEstimate: true, standardDeviation: 10)),
        WatchFormulationComponent(
          substanceName: "Caffeine",
          displayName: "Caffeine",
          route: "oral",
          units: "mg",
          dose: WatchDose(amount: nil, isEstimate: false, standardDeviation: nil)),
      ]))
  }

  private let pill = WatchCustomUnit(
    id: "x-coredata://unit",
    name: "Pink pill",
    singular: "pill",
    plural: "pills",
    dosePerUnit: 120,
    isEstimate: false)

  private func suggestion(units: String = "mg", customUnit: WatchCustomUnit? = nil, doses: [WatchDose]) -> WatchSuggestion {
    WatchSuggestion(
      id: "MDMAoral",
      substanceName: "MDMA",
      displayName: "MDMA",
      route: "oral",
      color: WatchColor(red: 1, green: 0, blue: 0.5),
      units: units,
      customUnit: customUnit,
      doses: doses)
  }

}
