import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class JournalBackupTests: XCTestCase {
  // Backups of every format version must keep importing. Never edit a fixture; add one for each new version.
  func testImportsVersion1Backups() throws {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Backup v1", withExtension: "json"))
    let backup = try XCTUnwrap(JournalBackup.read(Data(contentsOf: url)))
    let context = PersistenceController(inMemory: true).viewContext
    try backup.restore(into: context)
    try context.save()

    let experience = try XCTUnwrap(context.fetch(Experience.fetchRequest()).first)
    XCTAssertEqual(experience.title, "Saturday")
    XCTAssertTrue(experience.isFavorite)
    XCTAssertEqual(experience.sortDate, Date(timeIntervalSince1970: 1_795_287_600.25))
    let ingestions = experience.ingestionsSorted
    XCTAssertEqual(ingestions.map(\.substanceNameUnwrapped), ["MDMA", "Ketamine"])
    let mdma = ingestions[0]
    XCTAssertEqual(mdma.dose, 100)
    XCTAssertEqual(mdma.estimatedDoseStandardDeviation, 10)
    XCTAssertEqual(mdma.identifier, UUID(uuidString: "6F1F0F3E-2C4B-4E36-9F1D-3A1B2C3D4E5F"))
    XCTAssertEqual(mdma.location?.name, "Home")
    XCTAssertEqual(mdma.formulation?.componentsSorted.map(\.substanceNameUnwrapped), ["MDMA", "Caffeine"])
    XCTAssertEqual(mdma.webhookMessagesSorted.first?.webhookPreset?.name, "Friends")
    XCTAssertEqual(mdma.substanceCompanion?.color, .pink)
    let ketamine = ingestions[1]
    XCTAssertEqual(ketamine.consumerName, "Alex")
    XCTAssertEqual(ketamine.customUnit?.nameUnwrapped, "Spoon")
    XCTAssertEqual(ketamine.endTime, Date(timeIntervalSince1970: 1_795_297_500))
    XCTAssertEqual(experience.ratingsUnwrapped.first?.optionUnwrapped, .twoPlus)
    let note = try XCTUnwrap(experience.timedNotesSorted.first)
    XCTAssertEqual(note.webhookMessagesSorted.first?.messageId, "1300000000000000002")
    let companions = try context.fetch(SubstanceCompanion.fetchRequest())
    XCTAssertEqual(companions.first { $0.substanceName == "Caffeine" }?.color, .brown)
    XCTAssertEqual(try context.fetch(Spray.fetchRequest()).first?.numSprays, 100)
    XCTAssertEqual(try context.fetch(CustomRoa.fetchRequest()).first?.customSubstance?.name, "Coffee")
    XCTAssertEqual(try context.fetch(SubstanceOverride.fetchRequest()).first?.displayName, "K")
    XCTAssertEqual(backup.settings["webhookUsername"], .string("Sam"))

    let defaults = Self.emptyDefaults()
    let profile = AssistantProfile(preset: .onDevice)
    let profiles = try JSONEncoder().encode([profile])
    defaults.set(profiles, forKey: PersistenceController.assistantProfilesKey)
    defaults.set(profile.id.uuidString, forKey: PersistenceController.assistantActiveProfileKey)
    backup.restoreSettings(to: defaults)
    XCTAssertEqual(defaults.data(forKey: PersistenceController.assistantProfilesKey), profiles)
    XCTAssertEqual(defaults.string(forKey: PersistenceController.assistantActiveProfileKey), profile.id.uuidString)
  }

  func testVersion2BackupsRestoreAndExportModelConfiguration() throws {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Backup v2", withExtension: "json"))
    let fixture = try XCTUnwrap(JournalBackup.read(Data(contentsOf: url)))
    let context = PersistenceController(inMemory: true).viewContext
    try fixture.restore(into: context)
    try context.save()

    let defaults = Self.emptyDefaults()
    fixture.restoreSettings(to: defaults)
    let backup = try JournalBackup(context: context, defaults: defaults, appVersion: "1")
    let read = try XCTUnwrap(JournalBackup.read(backup.data()))
    let restored = Self.emptyDefaults()
    read.restoreSettings(to: restored)

    let profiles = AssistantProfileStore.profiles(from: restored.data(forKey: PersistenceController.assistantProfilesKey))
    XCTAssertEqual(profiles.map(\.preset), [.onDevice, .customOpenAI])
    let activeID = restored.string(forKey: PersistenceController.assistantActiveProfileKey)
    let active = try XCTUnwrap(profiles.first { $0.id.uuidString == activeID })
    XCTAssertEqual(active.name, "My Provider")
    XCTAssertEqual(active.standard, .openAIChat)
    XCTAssertEqual(active.baseURL, "https://example.com/v1")
    XCTAssertEqual(active.model, "primary-model")
    XCTAssertEqual(active.maxOutputTokens, 512)
    XCTAssertEqual(active.recentModels, ["previous-model"])

    let empty = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    empty.restoreSettings(to: restored)
    XCTAssertNil(restored.data(forKey: PersistenceController.assistantProfilesKey))
    XCTAssertNil(restored.string(forKey: PersistenceController.assistantActiveProfileKey))
  }

  func testRestoringModelConfigurationKeepsKeysWithTheirServer() throws {
    var local = AssistantProfile(preset: .customOpenAI)
    local.baseURL = "https://example.com/v1"
    let defaults = Self.emptyDefaults()
    defaults.set(try JSONEncoder().encode([local]), forKey: PersistenceController.assistantProfilesKey)
    let mayHaveKey: (UUID) -> Bool = { $0 == local.id }

    var exported = local
    exported.model = "restored-model"
    AssistantProfileStore.restore(
      profilesFrom: try JSONEncoder().encode([exported]),
      activeID: exported.id.uuidString,
      to: defaults,
      mayHaveKey: mayHaveKey)
    XCTAssertEqual(defaults.string(forKey: PersistenceController.assistantActiveProfileKey), local.id.uuidString)

    exported.baseURL = "https://other.example/v1"
    AssistantProfileStore.restore(
      profilesFrom: try JSONEncoder().encode([exported]),
      activeID: exported.id.uuidString,
      to: defaults,
      mayHaveKey: mayHaveKey)
    let profiles = AssistantProfileStore.profiles(from: defaults.data(forKey: PersistenceController.assistantProfilesKey))
    let restored = try XCTUnwrap(profiles.first)
    XCTAssertNotEqual(restored.id, local.id)
    XCTAssertEqual(restored.baseURL, exported.baseURL)
    XCTAssertEqual(defaults.string(forKey: PersistenceController.assistantActiveProfileKey), restored.id.uuidString)
  }

  // Anything in the journal comes back the same: an export of the restored journal equals the first one,
  // apart from the ids the backup gives its objects
  func testRestoresEverythingExactly() throws {
    let source = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: source)
    let backup = try JournalBackup(context: source, defaults: Self.emptyDefaults(), appVersion: "1")
    XCTAssertEqual(
      Set(backup.entities.keys),
      Set(source.persistentStoreCoordinator?.managedObjectModel.entities.compactMap(\.name) ?? []))
    XCTAssertTrue(backup.entities.values.allSatisfy { !$0.isEmpty }, "every entity has an object to compare")

    let read = try XCTUnwrap(JournalBackup.read(backup.fileData()))
    let target = PersistenceController(inMemory: true).viewContext
    try read.restore(into: target)
    try target.save()
    let restored = try JournalBackup(context: target, defaults: Self.emptyDefaults(), appVersion: "1")

    XCTAssertEqual(Self.canonical(restored), Self.canonical(backup))
  }

  func testRestoringReplacesWhatWasThere() throws {
    let context = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: context)
    let backup = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    try backup.restore(into: context)
    try context.save()
    for (entity, records) in backup.entities {
      XCTAssertEqual(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: entity)), records.count, entity)
    }
  }

  func testSettingsComeBackWithTheirTypes() throws {
    let source = Self.emptyDefaults()
    source.set(true, forKey: PersistenceController.isHidingDosageDotsKey)
    source.set(48, forKey: PersistenceController.dynamicExperienceRangeHoursKey)
    source.set("Sam", forKey: PersistenceController.webhookUsernameKey)
    source.set(Data([1, 2, 3]), forKey: PersistenceController.leaderboardServersKey)
    source.set(true, forKey: PersistenceController.isICloudSyncEnabledKey)
    let backup = try JournalBackup(
      context: PersistenceController(inMemory: true).viewContext,
      defaults: source,
      appVersion: "1")
    let read = try XCTUnwrap(JournalBackup.read(backup.data()))

    let target = Self.emptyDefaults()
    target.set("Someone else", forKey: PersistenceController.webhookTemplateKey)
    read.restoreSettings(to: target)
    XCTAssertTrue(target.bool(forKey: PersistenceController.isHidingDosageDotsKey))
    XCTAssertEqual(target.object(forKey: PersistenceController.dynamicExperienceRangeHoursKey) as? Int, 48)
    XCTAssertEqual(target.string(forKey: PersistenceController.webhookUsernameKey), "Sam")
    XCTAssertEqual(target.data(forKey: PersistenceController.leaderboardServersKey), Data([1, 2, 3]))
    // Not in the backup, so back to its default
    XCTAssertNil(target.object(forKey: PersistenceController.webhookTemplateKey))
    // About the device, so neither written nor restored
    XCTAssertNil(read.settings[PersistenceController.isICloudSyncEnabledKey])
  }

  func testDatesKeepMicroseconds() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
    XCTAssertEqual(BackupDate.string(from: date), "2023-11-14T22:13:20.123456Z")
    let read = try XCTUnwrap(BackupDate.date(from: "2023-11-14T22:13:20.123456Z"))
    XCTAssertEqual(read.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.000_001)
    XCTAssertEqual(BackupDate.date(from: "2023-11-14T22:13:20Z"), Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(BackupDate.date(from: "2023-11-14T22:13:20.5Z"), Date(timeIntervalSince1970: 1_700_000_000.5))
    XCTAssertEqual(BackupDate.string(from: Date(timeIntervalSince1970: 0.9999999)), "1970-01-01T00:00:01.000000Z")
    XCTAssertNil(BackupDate.date(from: "2023-11-14"))
  }

  func testRefusesBackupsOfNewerVersions() {
    let data = Data(#"{"format": "FreakLog Backup", "formatVersion": 99}"#.utf8)
    XCTAssertThrowsError(try JournalBackup.read(data)) { error in
      XCTAssertEqual(error as? JournalBackupError, .newerFormat(99))
    }
  }

  func testOtherFilesAreNotBackups() throws {
    let journalFile = JournalFile(experiences: [], customSubstances: [], customUnits: [])
    XCTAssertNil(try JournalBackup.read(JSONEncoder().encode(journalFile)))
    XCTAssertNil(try JournalBackup.read(Data("not json".utf8)))
  }

  func testBackupContainerFailsLegacyJSONParsingAndKeepsV1Payload() throws {
    let context = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: context)
    let backup = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    let file = try backup.fileData()
    XCTAssertThrowsError(try JSONSerialization.jsonObject(with: file))
    XCTAssertThrowsError(try JournalFile.read(file))
    let reopened = try XCTUnwrap(JournalBackup.read(file))
    XCTAssertEqual(reopened.entities, backup.entities)
    XCTAssertEqual(reopened.settings, backup.settings)
    XCTAssertThrowsError(try JournalBackup.read(Data("FREAKLOG-BACKUP/2\n{}".utf8))) { error in
      XCTAssertEqual(error as? JournalBackupError, .invalidContainer)
    }
  }

  func testUnknownFormatNeverFallsThroughToJournal() {
    for json in [#"{"format":"Other Backup","experiences":[]}"#, #"{"formatVersion":1,"experiences":[]}"#] {
      let data = Data(json.utf8)
      XCTAssertThrowsError(try JournalBackup.read(data)) { error in
        XCTAssertEqual(error as? JournalBackupError, .unrecognizedFormat)
      }
      XCTAssertThrowsError(try JournalFile.read(data))
    }
  }

  func testIncompleteBackupIsRejectedBeforeStagingDeletes() throws {
    let context = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: context)
    let original = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    var missingEntity = original
    missingEntity.entities.removeValue(forKey: "Ingestion")
    for data in try [missingEntity.fileData(), missingEntity.data()] {
      let imported = try XCTUnwrap(JournalBackup.read(data))
      XCTAssertThrowsError(try imported.restore(into: context)) { error in
        XCTAssertEqual(error as? JournalBackupError, .missingEntity("Ingestion"))
      }
    }
    var missingField = original
    missingField.entities["Ingestion"]?[0].attributes.removeValue(forKey: "substanceName")
    let incomplete = try XCTUnwrap(JournalBackup.read(missingField.fileData()))
    XCTAssertThrowsError(try incomplete.restore(into: context)) { error in
      XCTAssertEqual(error as? JournalBackupError, .missingProperty(entity: "Ingestion", name: "substanceName"))
    }
    XCTAssertFalse(context.hasChanges)
    XCTAssertGreaterThan(try context.count(for: Ingestion.fetchRequest()), 0)
  }

  func testABrokenBackupLeavesTheJournalAlone() throws {
    let context = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: context)
    var backup = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    var ingestions = try XCTUnwrap(backup.entities["Ingestion"])
    ingestions[0].relationships["experience"] = .string("missing")
    backup.entities["Ingestion"] = ingestions
    let countBefore = try context.count(for: Ingestion.fetchRequest())

    XCTAssertThrowsError(try backup.restore(into: context))
    context.rollback()
    XCTAssertEqual(try context.count(for: Ingestion.fetchRequest()), countBefore)
  }

  func testUpgradeStepsCanRenameAttributes() throws {
    var json = try JSONDecoder().decode(JSONValue.self, from: Data(##"""
      {"entities": {"Ingestion": [{"id": "1", "attributes": {"oldName": "x"}, "relationships": {}}]}}
      """##.utf8))
    try JournalBackup.renameAttribute("oldName", to: "note", of: "Ingestion", in: &json)
    let attributes = json.object?["entities"]?.object?["Ingestion"]
    XCTAssertEqual(
      attributes,
      .array([.object(["id": .string("1"), "attributes": .object(["note": .string("x")]), "relationships": .object([:])])]))
  }

  // Changing the data model needs a new format version (see JournalBackup), so this fails until it gets one
  func testTheFormatFollowsTheDataModel() throws {
    let versionInfo = try XCTUnwrap(
      Bundle.main.url(forResource: "Main", withExtension: "momd")?.appendingPathComponent("VersionInfo.plist"))
    let info = try XCTUnwrap(NSDictionary(contentsOf: versionInfo))
    XCTAssertEqual(
      info["NSManagedObjectModel_CurrentVersionName"] as? String,
      JournalBackup.dataModelVersion,
      "The data model changed: bump JournalBackup.formatVersion, add an upgrade step if needed and a fixture")
  }

  // MARK: - Helpers

  private static func emptyDefaults() -> UserDefaults {
    let name = "JournalBackupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  // Each record with its relationships pointing at the attributes of the related records instead of ids
  private static func canonical(_ backup: JournalBackup) -> [String: [String]] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let encode = { (value: JSONValue) in String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self) }
    var fingerprints: [String: String] = [:]
    for records in backup.entities.values {
      for record in records {
        fingerprints[record.id] = encode(.object(record.attributes))
      }
    }
    let resolve = { (value: JSONValue) -> JSONValue in
      switch value {
      case .string(let id): .string(fingerprints[id] ?? "missing")
      case .array(let ids): .array(ids.compactMap { $0.string.map { .string(fingerprints[$0] ?? "missing") } }.sorted {
          encode($0) < encode($1)
        })
      default: value
      }
    }
    return backup.entities.mapValues { records in
      records.map { record in
        encode(.object([
          "attributes": .object(record.attributes),
          "relationships": .object(record.relationships.mapValues(resolve)),
        ]))
      }.sorted()
    }
  }

  // At least one object of every entity, with unusual values: estimates, sub-millisecond times, nil fields
  private static func fillEveryEntity(in context: NSManagedObjectContext) throws {
    let start = Date(timeIntervalSince1970: 1_763_751_600.123456)
    let experience = Experience.create(at: start, title: "Saturday", in: context)
    experience.isFavorite = true
    experience.text = "Notes"
    let legacyLocation = ExperienceLocation(context: context)
    legacyLocation.name = "Old place"
    legacyLocation.latitude = 1.5
    experience.legacyLocation = legacyLocation

    let companion = SubstanceCompanion(context: context)
    companion.substanceName = "MDMA"
    companion.colorAsText = SubstanceColor.pink.rawValue
    let unusedCompanion = SubstanceCompanion(context: context)
    unusedCompanion.substanceName = "Caffeine"
    unusedCompanion.colorAsText = "#123456"

    let unit = CustomUnit(context: context)
    unit.name = "Spoon"
    unit.substanceName = "Ketamine"
    unit.dose = 20
    unit.idForAndroid = 7
    unit.isArchived = true

    let formulation = FormulationCodable(
      name: "Party pill",
      note: "",
      creationDate: start,
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
          dose: nil,
          units: "mg",
          isEstimate: false,
          estimatedDoseStandardDeviation: nil),
      ]).insert(into: context)

    let ingestion = Ingestion(context: context)
    ingestion.identifier = UUID()
    ingestion.substanceName = "MDMA"
    ingestion.time = start
    ingestion.endTime = start.addingTimeInterval(600.000001)
    ingestion.creationDate = Date()
    ingestion.dose = 150
    ingestion.isEstimate = true
    ingestion.estimatedDoseStandardDeviation = 12.5
    ingestion.units = "mg"
    ingestion.administrationRoute = AdministrationRoute.oral.rawValue
    ingestion.consumerName = "Alex"
    ingestion.note = "Line\nbreak and \"quotes\""
    ingestion.formulation = formulation
    ingestion.formulationAmount = 1.5
    ingestion.customUnit = unit
    ingestion.substanceCompanion = companion
    ingestion.experience = experience
    let location = ExperienceLocation(context: context)
    location.name = "Home"
    location.latitude = 52.520008
    location.longitude = 13.404954
    ingestion.location = location

    let rating = ShulginRating(context: context)
    rating.option = ShulginRatingOption.threePlus.rawValue
    rating.creationDate = start
    rating.experience = experience
    let note = TimedNote(context: context)
    note.note = "Peaking"
    note.time = start.addingTimeInterval(3600)
    note.colorAsText = "#63E6E2"
    note.isPartOfTimeline = true
    note.experience = experience

    let preset = WebhookPreset(context: context)
    preset.id = UUID()
    preset.name = "Friends"
    preset.url = "https://example.com/hook"
    preset.isEnabled = true
    for (index, owner) in [ingestion as NSManagedObject, note].enumerated() {
      let message = WebhookMessage(context: context)
      message.id = UUID()
      message.messageId = "\(index)"
      message.webhookPreset = preset
      message.ingestion = owner as? Ingestion
      message.timedNote = owner as? TimedNote
    }

    let customSubstance = CustomSubstance(context: context)
    customSubstance.name = "Coffee"
    customSubstance.units = "cups"
    let roa = CustomRoa(context: context)
    roa.substanceName = "Coffee"
    roa.administrationRoute = AdministrationRoute.oral.rawValue
    roa.commonDose = 1
    roa.onsetLow = 10
    roa.customSubstance = customSubstance
    let override = SubstanceOverride(context: context)
    override.substanceName = "Ketamine"
    override.displayName = "K"
    let spray = Spray(context: context)
    spray.name = "Nasal"
    spray.contentInMl = 10
    spray.numSprays = 100
    spray.isPreferred = true
    try context.save()
  }
}
