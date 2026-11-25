import CoreData
import XCTest
@testable import FreakLog

// MARK: - FormulationTests

@MainActor
final class FormulationTests: XCTestCase {
  func testAmountScalesDosesAndDeviations() {
    let arguments = sample.ingestionArguments(amount: 1.5)
    XCTAssertEqual(arguments.map(\.substanceName), ["MDMA", "Caffeine", "Ketamine"])
    XCTAssertEqual(arguments[0].dose, 150)
    XCTAssertEqual(arguments[0].estimatedDoseStandardDeviation, 15)
    XCTAssertTrue(arguments[0].isEstimate)
    XCTAssertEqual(arguments[1].dose, 75)
    XCTAssertNil(arguments[1].estimatedDoseStandardDeviation)
    XCTAssertNil(arguments[2].dose)
    XCTAssertEqual(arguments[2].administrationRoute, .insufflated)
    XCTAssertEqual(arguments[2].units, "mg")
  }

  func testComponentsKeepTheirOrderWhenSaved() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: context)
    try context.save()
    XCTAssertEqual(formulation.componentsSorted.map(\.substanceNameUnwrapped), ["MDMA", "Caffeine", "Ketamine"])

    var edited = FormulationCodable(formulation)
    edited.components.reverse()
    edited.components.removeLast()
    edited.apply(to: formulation)
    try context.save()
    XCTAssertEqual(formulation.componentsSorted.map(\.substanceNameUnwrapped), ["Ketamine", "Caffeine"])
    XCTAssertEqual(try context.count(for: FormulationComponent.fetchRequest()), 2)
  }

  func testNestedBlendsKeepScaledLeafSnapshotsAcrossEditsAndBackups() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let ingredient = sample.insert(into: source)
    var middle = FormulationCodable(name: "Middle", note: "", creationDate: .now, components: [])
    middle.components = try XCTUnwrap(ingredient.includedProduct.leaves(quantity: 1.5))
    let middleObject = middle.insert(into: source)
    var outer = FormulationCodable(name: "Outer", note: "", creationDate: .now, components: [])
    outer.components = try XCTUnwrap(middleObject.includedProduct.leaves(quantity: 2))
    let outerObject = outer.insert(into: source)

    var changed = sample
    changed.components[0].dose = 1
    changed.apply(to: ingredient)
    source.delete(middleObject)
    try source.save()

    let args = outerObject.ingestionArguments(amount: 2)
    XCTAssertEqual(args.map(\.dose), [600, 300, nil])
    XCTAssertEqual(args[0].estimatedDoseStandardDeviation, 60)
    XCTAssertEqual(args.map(\.units), ["mg", "mg", "mg"])
    XCTAssertTrue(args.allSatisfy { $0.formulation == outerObject && $0.formulationAmount == 2 })

    let target = PersistenceController(inMemory: true).viewContext
    let backup = try JournalBackup(context: source, appVersion: "test").fileData()
    try XCTUnwrap(JournalBackup.read(backup)).restore(into: target)
    let restored = try XCTUnwrap(target.fetch(Formulation.fetchRequest()).first { $0.name == outer.name })
    XCTAssertEqual(restored.blendIdentifier, outerObject.blendIdentifier)
    XCTAssertEqual(restored.componentsSorted[0].blendPath.map(\.name), ["Middle", sample.name])
    XCTAssertEqual(restored.componentsSorted[0].blendPath.map(\.quantity), [2, 1.5])
    XCTAssertEqual(restored.ingestionArguments(amount: 2).map(\.dose), args.map(\.dose))

    let portable = try JSONEncoder().encode(FormulationCodable(restored))
    let decoded = try JSONDecoder().decode(FormulationCodable.self, from: portable)
    XCTAssertEqual(decoded.components.map(\.withoutID), FormulationCodable(restored).components.map(\.withoutID))
  }

  func testBlendCycleDetectionUsesIdentityRatherThanName() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let first = sample.insert(into: context)
    let sameName = sample.insert(into: context)
    let firstValues = FormulationCodable(first)
    XCTAssertFalse(firstValues.canInclude(first.includedProduct))
    XCTAssertTrue(firstValues.canInclude(sameName.includedProduct))
    var secondValues = FormulationCodable(sameName)
    secondValues.components = try XCTUnwrap(first.includedProduct.leaves(quantity: 1))
    secondValues.apply(to: sameName)
    XCTAssertFalse(firstValues.canInclude(sameName.includedProduct))
  }

  func testIncludedCustomUnitsKeepTheOriginalConversion() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let unit = CustomUnit(context: context)
    unit.name = "Test unit"
    unit.substanceName = "Caffeine"
    unit.administrationRoute = "oral"
    unit.unit = "capsule"
    unit.originalUnit = "mg"
    unit.dose = 30
    unit.isEstimate = true
    unit.estimatedDoseStandardDeviation = 2
    let snapshotted = try XCTUnwrap(unit.includedProduct.leaves(quantity: 1.5))
    unit.dose = 50
    let component = try XCTUnwrap(snapshotted.first)
    XCTAssertEqual(component.dose, 45)
    XCTAssertEqual(component.units, "mg")
    XCTAssertEqual(component.estimatedDoseStandardDeviation, 3)
    XCTAssertEqual(component.blendPath.first?.kind, .customUnit)
  }

  func testExportedFormulationsImportTheSameData() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: source)
    let file = try JournalFile(experiences: [], customSubstances: [], customUnits: [], formulations: [formulation])
    let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
    let target = PersistenceController(inMemory: true).viewContext
    decoded.insert(into: target)

    let imported = try XCTUnwrap(target.fetch(Formulation.fetchRequest()).first)
    let values = FormulationCodable(imported)
    XCTAssertEqual(values.name, sample.name)
    XCTAssertEqual(values.note, sample.note)
    XCTAssertEqual(values.creationDate, sample.creationDate)
    XCTAssertEqual(values.components.map(\.withoutID), sample.components.map(\.withoutID))
  }

  func testOlderFilesWithoutFormulationsStillImport() throws {
    let file = try JSONDecoder().decode(JournalFile.self, from: Data(#"{"experiences": []}"#.utf8))
    XCTAssertTrue(file.formulations.isEmpty)
  }

  func testDeletingAFormulationDeletesItsComponents() throws {
    let context = PersistenceController(inMemory: true).viewContext
    context.delete(sample.insert(into: context))
    try context.save()
    XCTAssertEqual(try context.count(for: FormulationComponent.fetchRequest()), 0)
  }

  func testFormulationIngestionsAreSuggestedAsTheFormulation() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let formulation = sample.insert(into: context)
    var ingestions = [Ingestion]()
    for (index, arguments) in formulation.ingestionArguments(amount: 1.5).enumerated() {
      let ingestion = Ingestion(context: context)
      ingestion.substanceName = arguments.substanceName
      ingestion.administrationRoute = arguments.administrationRoute.rawValue
      ingestion.dose = arguments.dose ?? 0
      ingestion.units = arguments.units
      ingestion.formulation = arguments.formulation
      ingestion.formulationAmount = arguments.formulationAmount ?? 0
      ingestion.creationDate = Date(timeIntervalSince1970: 2_000 + Double(index))
      ingestions.append(ingestion)
    }
    let alone = Ingestion(context: context)
    alone.substanceName = "MDMA"
    alone.administrationRoute = AdministrationRoute.oral.rawValue
    alone.dose = 80
    alone.units = "mg"
    alone.creationDate = Date(timeIntervalSince1970: 1_000)
    ingestions.append(alone)

    let suggestions = getSuggestions(sortedIngestions: ingestions, customUnits: [])
    let formulationSuggestions = suggestions.compactMap { $0 as? FormulationSuggestions }
    XCTAssertEqual(formulationSuggestions.map(\.formulation), [formulation])
    XCTAssertEqual(formulationSuggestions.first?.amounts, [1.5])
    XCTAssertTrue(suggestions.first is FormulationSuggestions)
    let pure = suggestions.compactMap { $0 as? PureSubstanceSuggestions }
    XCTAssertEqual(pure.map(\.substance.name), ["MDMA"])
    XCTAssertEqual(pure.first?.dosesAndUnit.map(\.dose), [80])
  }

  func testIngestionsKeepTheirFormulationThroughExportWhenNamesMatch() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let other = sample.insert(into: source)
    other.note = "Different formulation with the same name"
    let formulation = sample.insert(into: source)
    let experience = Experience.create(at: Date(timeIntervalSince1970: 5_000), title: "Test", in: source)
    let ingestion = Ingestion(context: source)
    ingestion.substanceName = "MDMA"
    ingestion.time = Date(timeIntervalSince1970: 5_000)
    ingestion.administrationRoute = AdministrationRoute.oral.rawValue
    ingestion.formulation = formulation
    ingestion.formulationAmount = 2
    ingestion.experience = experience
    let file = try JournalFile(experiences: [experience], customSubstances: [], customUnits: [], formulations: [other, formulation])
    let decoded = try JSONDecoder().decode(JournalFile.self, from: JSONEncoder().encode(file))
    let target = PersistenceController(inMemory: true).viewContext
    decoded.insert(into: target)

    let imported = try XCTUnwrap(target.fetch(Ingestion.fetchRequest()).first)
    XCTAssertEqual(imported.formulation?.nameUnwrapped, "Party pill")
    XCTAssertEqual(imported.formulation?.note, formulation.note)
    XCTAssertEqual(imported.formulationAmount, 2)

    let data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
    var oldRecords = try XCTUnwrap(data["experiences"] as? [[String: Any]])
    var oldIngestions = try XCTUnwrap(oldRecords[0]["ingestions"] as? [[String: Any]])
    oldIngestions[0].removeValue(forKey: "formulationId")
    oldRecords[0]["ingestions"] = oldIngestions
    var oldJSON = data
    oldJSON["experiences"] = oldRecords
    let oldFile = try JournalFile.read(JSONSerialization.data(withJSONObject: oldJSON))
    let oldTarget = PersistenceController(inMemory: true).viewContext
    oldFile.insert(into: oldTarget)
    XCTAssertNil(try oldTarget.fetch(Ingestion.fetchRequest()).first?.formulation)
  }

  private let sample = FormulationCodable(
    name: "Party pill",
    note: "Tested",
    creationDate: Date(timeIntervalSince1970: 1_000),
    components: [
      .init(
        substanceName: "MDMA",
        administrationRoute: .oral,
        dose: 100,
        units: "mg",
        isEstimate: true,
        estimatedDoseStandardDeviation: 10),
      .init(
        substanceName: "Caffeine",
        administrationRoute: .oral,
        dose: 50,
        units: "mg",
        isEstimate: false,
        estimatedDoseStandardDeviation: nil),
      .init(
        substanceName: "Ketamine",
        administrationRoute: .insufflated,
        dose: nil,
        units: "mg",
        isEstimate: false,
        estimatedDoseStandardDeviation: nil),
    ])
}

extension FormulationCodable.Component {
  // Ids only tell components apart while editing
  fileprivate var withoutID: Self {
    var copy = self
    copy.id = UUID(uuid: UUID_NULL)
    return copy
  }
}

@MainActor
final class RoutineOccurrenceTests: XCTestCase {
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    return result
  }

  func testLegacyRoutineStillSchedulesAndTimeEditRetainsOccurrenceIdentity() throws {
    let data = Data(#"{"id":"37E9A223-1E5B-4191-A16A-7785D8A196AC","name":"Routine","hour":9,"minute":0,"reminds":false}"#.utf8)
    var schedule = try JSONDecoder().decode(RoutineSchedule.self, from: data)
    XCTAssertTrue(schedule.isValid)
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
    let initial = try XCTUnwrap(schedule.slot(on: day, calendar: calendar))
    XCTAssertNil(schedule.productKind)
    schedule.hour = 10
    let changed = try XCTUnwrap(schedule.slot(on: day, calendar: calendar))
    XCTAssertEqual(initial.id, changed.id)
    XCTAssertNotEqual(initial.scheduledAt, changed.scheduledAt)
  }

  func testRoutineAndProductLinksSurviveBackupAndDuplicateLogIsRejected() throws {
    let source = PersistenceController(inMemory: true).viewContext
    let schedule = RoutineSchedule(name: "Routine", hour: 9, minute: 0, productKind: .customUnit, productAmount: 1)
    let record = RoutineRecord(context: source)
    record.id = schedule.id
    record.scheduleData = try JSONEncoder().encode(schedule)
    let unit = CustomUnit(context: source)
    unit.name = "Saved Product"
    record.customUnit = unit

    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
    let slot = try XCTUnwrap(schedule.slot(on: day, calendar: calendar))
    let occurrence = try XCTUnwrap(RoutineSchedules.stageLog(for: slot, in: source))
    let ingestion = Ingestion(context: source)
    ingestion.time = slot.scheduledAt.addingTimeInterval(60)
    ingestion.experience = Experience.create(at: try XCTUnwrap(ingestion.time), title: "Example", in: source)
    ingestion.customUnit = unit
    ingestion.routineOccurrence = occurrence
    try source.save()

    let data = try JournalBackup(context: source, appVersion: "test").fileData()
    let target = PersistenceController(inMemory: true).viewContext
    try XCTUnwrap(JournalBackup.read(data)).restore(into: target)
    let imported = try XCTUnwrap(target.fetch(Ingestion.fetchRequest()).first)
    XCTAssertEqual(imported.routineOccurrence?.scheduledAt, slot.scheduledAt)
    XCTAssertEqual(imported.routineOccurrence?.loggedExperience?.title, "Example")
    XCTAssertEqual(imported.routineOccurrence?.routine?.schedule, schedule)
    XCTAssertEqual(imported.routineOccurrence?.routine?.customUnit, imported.customUnit)
    XCTAssertNil(try RoutineSchedules.stageLog(for: slot, in: target))
    XCTAssertEqual(try target.count(for: RoutineOccurrence.fetchRequest()), 1)

    target.delete(imported)
    try target.save()
    XCTAssertNotNil(try RoutineSchedules.stageLog(for: slot, in: target))
  }

  func testFixedIntervalsUseCalendarDaysAcrossDaylightSaving() throws {
    var calendar = self.calendar
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
    let schedule = RoutineSchedule(
      name: "Routine", hour: 9, minute: 0, intervalDays: 2, anchorDay: .init(anchor, calendar: calendar))
    XCTAssertTrue(schedule.isValid)
    let first = try XCTUnwrap(schedule.slot(on: anchor, calendar: calendar))
    let skippedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: anchor))
    XCTAssertNil(schedule.slot(on: skippedDay, calendar: calendar))
    let second = try XCTUnwrap(schedule.nextIntervalSlots(after: first.scheduledAt, calendar: calendar, limit: 1).first)
    XCTAssertEqual(calendar.component(.day, from: second.scheduledAt), 9)
    XCTAssertEqual(calendar.component(.hour, from: second.scheduledAt), 9)
    XCTAssertEqual(second.scheduledAt.timeIntervalSince(first.scheduledAt), 47 * 60 * 60)
  }

  func testAdditionalTimesHaveStableIndependentOccurrences() throws {
    var schedule = RoutineSchedule(
      name: "Routine", hour: 9, minute: 0, additionalTimes: [.init(hour: 18, minute: 0)])
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
    let original = schedule.slots(on: day, calendar: calendar)
    XCTAssertEqual(original.count, 2)
    XCTAssertNotEqual(original[0].id, original[1].id)
    schedule.additionalTimes?[0].hour = 19
    let edited = schedule.slots(on: day, calendar: calendar)
    XCTAssertEqual(original.map(\.id), edited.map(\.id))
    XCTAssertNotEqual(original[1].scheduledAt, edited[1].scheduledAt)
    schedule.additionalTimes?[0].hour = 9
    XCTAssertFalse(schedule.isValid)
  }

  func testRoutinePauseEndDateAndSlotAmounts() throws {
    let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
    let lastDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
    let afterEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: lastDay))
    var schedule = RoutineSchedule(
      name: "Routine", hour: 9, minute: 0, productKind: .customUnit, productAmount: 1,
      additionalTimes: [.init(hour: 18, minute: 0, productAmount: 2)],
      endDay: .init(lastDay, calendar: calendar))
    let first = schedule.slots(on: firstDay, calendar: calendar)
    XCTAssertEqual(first.map(schedule.amount(for:)), [1, 2])
    XCTAssertEqual(schedule.slots(on: lastDay, calendar: calendar).count, 2)
    XCTAssertTrue(schedule.slots(on: afterEnd, calendar: calendar).isEmpty)

    let noon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: firstDay))
    schedule.setPaused(true, at: noon)
    XCTAssertEqual(schedule.slots(on: firstDay, calendar: calendar).map(\.id), [first[0].id])
    XCTAssertTrue(schedule.slots(on: lastDay, calendar: calendar).isEmpty)
    schedule.setPaused(false, at: lastDay)
    XCTAssertEqual(schedule.slots(on: firstDay, calendar: calendar).map(\.id), [first[0].id])
    XCTAssertEqual(schedule.slots(on: lastDay, calendar: calendar).count, 2)

    let copy = schedule.duplicate(at: firstDay, calendar: calendar)
    XCTAssertNotEqual(copy.id, schedule.id)
    XCTAssertNotEqual(copy.additionalTimes?.first?.id, schedule.additionalTimes?.first?.id)
    XCTAssertEqual(copy.slots(on: firstDay, calendar: calendar).map(copy.amount(for:)), [1, 2])
  }
}
