import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class JournalBackupTests: XCTestCase {
  func testRemovedSaferTabDoesNotResetHiddenTabs() throws {
    let suite = "TabVisibilityTests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("[\"stats\",\"safer\"]", forKey: PersistenceController.hiddenTabsKey)

    let tabs = TabManager(defaults: defaults)
    XCTAssertEqual(tabs.hiddenTabs, [.stats])
    XCTAssertTrue(tabs.enabledTabs.contains(.tools))

    tabs.setVisibility(for: .tools, isVisible: false)
    XCTAssertEqual(TabManager(defaults: defaults).hiddenTabs, [.stats, .tools])

    defaults.set("[\"substances\",\"tools\",\"safer\"]", forKey: PersistenceController.hiddenTabsKey)
    tabs.reload()
    XCTAssertEqual(tabs.hiddenTabs, [.substances, .tools])
  }

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
    XCTAssertEqual(mdma.location?.latitudeUnwrapped, 52.52)
    XCTAssertEqual(mdma.location?.longitudeUnwrapped, 13.405)
    XCTAssertEqual(mdma.formulation?.componentsSorted.map(\.substanceNameUnwrapped), ["MDMA", "Caffeine"])
    XCTAssertEqual(mdma.webhookMessagesSorted.first?.webhookPreset?.name, "Friends")
    XCTAssertNil(mdma.webhookMessagesSorted.first?.destinationURL)
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
    let original = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Backup v1", withExtension: "json"))
    let decoder = JSONDecoder()
    let settingsFixture = try decoder.decode(JournalBackup.self, from: Data(contentsOf: url))
    var journalFixture = try decoder.decode(JournalBackup.self, from: Data(contentsOf: original))
    journalFixture.formatVersion = 2
    journalFixture.settings = settingsFixture.settings
    let fixture = try XCTUnwrap(JournalBackup.read(journalFixture.data()))
    let context = PersistenceController(inMemory: true).viewContext
    try fixture.restore(into: context)
    try context.save()
    XCTAssertEqual(try context.fetch(Ingestion.fetchRequest()).count, 2)

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

  func testMalformedAssistantProfilesDoNotReplaceSettings() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let defaults = Self.emptyDefaults()
    let profile = AssistantProfile(preset: .onDevice)
    let profiles = try JSONEncoder().encode([profile])
    defaults.set(profiles, forKey: PersistenceController.assistantProfilesKey)
    defaults.set(profile.id.uuidString, forKey: PersistenceController.assistantActiveProfileKey)
    var backup = try JournalBackup(context: context, defaults: defaults, appVersion: "1")
    backup.settings[PersistenceController.assistantProfilesKey] = .string("invalid")

    XCTAssertThrowsError(try JournalBackup.read(backup.data())) {
      XCTAssertEqual($0 as? JournalBackupError, .invalidAssistantSettings)
    }
    XCTAssertThrowsError(try backup.restore(into: context)) {
      XCTAssertEqual($0 as? JournalBackupError, .invalidAssistantSettings)
    }
    backup.restoreSettings(to: defaults)
    XCTAssertEqual(defaults.data(forKey: PersistenceController.assistantProfilesKey), profiles)
    XCTAssertEqual(defaults.string(forKey: PersistenceController.assistantActiveProfileKey), profile.id.uuidString)
  }

  func testInvalidLocalAssistantProfilesPreventCreatingAnUnreadableBackup() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let defaults = Self.emptyDefaults()
    defaults.set(Data("invalid".utf8), forKey: PersistenceController.assistantProfilesKey)

    XCTAssertThrowsError(try JournalBackup(context: context, defaults: defaults, appVersion: "1")) {
      XCTAssertEqual($0 as? JournalBackupError, .invalidAssistantSettings)
    }
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

  func testImportsVersion2Backups() throws {
    let backup = try XCTUnwrap(JournalBackup.read(Self.version2Fixture))
    let context = PersistenceController(inMemory: true).viewContext
    try backup.restore(into: context)
    try context.save()

    let location = try XCTUnwrap(context.fetch(ExperienceLocation.fetchRequest()).first)
    XCTAssertEqual(location.latitudeUnwrapped, 0)
    XCTAssertNil(location.longitudeUnwrapped)
    XCTAssertEqual(
      try context.fetch(WebhookMessage.fetchRequest()).first?.destinationURL,
      "https://example.com/hook")
    XCTAssertEqual(Set(backup.entities.keys).intersection(["RoutineRecord", "RoutineOccurrence", "StockContainer", "StockChange"]).count, 4)
  }

  func testImportsVersion3Backups() throws {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Backup v3", withExtension: "json"))
    let backup = try XCTUnwrap(JournalBackup.read(Data(contentsOf: url)))
    let context = PersistenceController(inMemory: true).viewContext
    try backup.restore(into: context)
    try context.save()

    let ingestion = try XCTUnwrap(context.fetch(Ingestion.fetchRequest()).first)
    XCTAssertEqual(ingestion.substanceName, "Example")
    XCTAssertFalse(ingestion.isHiddenInTimeline)
    XCTAssertTrue(ingestion.substanceCompanion?.isHiddenInTimeline == true)
    XCTAssertEqual(ingestion.stomachFullness, "halfFull")
  }

  func testValidationUsesTheRestoreAndLeavesTheJournalUntouched() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let original = Experience(context: context)
    original.title = "Existing entry"
    try context.save()
    let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
    var backup = try XCTUnwrap(JournalBackup.read(Self.version2Fixture))

    try backup.validateContents(in: model)
    backup.entities["ExperienceLocation"]?[0].relationships["legacyExperience"] = .string("missing-experience")
    XCTAssertThrowsError(try backup.validateContents(in: model)) { error in
      XCTAssertEqual(error as? JournalBackupError, .unknownObject("missing-experience"))
    }
    XCTAssertEqual(try context.fetch(Experience.fetchRequest()), [original])
  }

  func testAutomaticBackupVerificationRejectsAnUnrestorableCopy() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
    var backup = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "Test")
    let passphrase = "Test passphrase"
    let valid = try backup.fileData()
    let sealed = try JournalBackupProtection.protect(valid, passphrase: passphrase)
    XCTAssertNoThrow(try JournalAutomaticBackups.verifySavedCopy(
      sealed, expectedPlaintext: valid, passphrase: passphrase, model: model
    ))

    backup.entities.removeValue(forKey: "Experience")
    let incomplete = try backup.fileData()
    let invalid = try JournalBackupProtection.protect(incomplete, passphrase: passphrase)
    XCTAssertThrowsError(try JournalAutomaticBackups.verifySavedCopy(
      invalid, expectedPlaintext: incomplete, passphrase: passphrase, model: model
    )) { error in
      XCTAssertEqual(error as? JournalBackupError, .missingEntity("Experience"))
    }
  }

  func testProtectedBackupsUseTheSameValidationAsPlainBackups() throws {
    let original = Self.version2Fixture
    let passphrase = "réveil-inventory-backup"
    let protected = try JournalBackupProtection.protect(original, passphrase: passphrase)
    XCTAssertTrue(JournalBackupProtection.isProtected(protected))
    XCTAssertFalse(JournalBackupProtection.isProtected(original))
    let decrypted = try JournalBackupProtection.open(protected, passphrase: "re\u{301}veil-inventory-backup")
    XCTAssertEqual(decrypted, original)

    let backup = try XCTUnwrap(JournalBackup.read(decrypted))
    let context = PersistenceController(inMemory: true).viewContext
    let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
    try backup.validateContents(in: model)
    XCTAssertThrowsError(try JournalBackupProtection.open(protected, passphrase: "wrong-passphrase")) { error in
      XCTAssertEqual(error as? JournalBackupProtection.Failure, .authentication)
    }
    var tampered = protected
    tampered[tampered.index(before: tampered.endIndex)] ^= 1
    XCTAssertThrowsError(try JournalBackupProtection.open(tampered, passphrase: passphrase)) { error in
      XCTAssertEqual(error as? JournalBackupProtection.Failure, .authentication)
    }
    XCTAssertThrowsError(try JournalBackupProtection.validateEnvelope(Data(protected.prefix(19)))) { error in
      XCTAssertEqual(error as? JournalBackupProtection.Failure, .damaged)
    }
  }

  func testReadsInventoryBackupFixtures() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let version5URL = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "Backup v5", withExtension: "json"))
    let version5 = try XCTUnwrap(JournalBackup.read(Data(contentsOf: version5URL)))
    try version5.restore(into: context)
    try context.save()
    let ingestion = try XCTUnwrap(context.fetch(Ingestion.fetchRequest()).first)
    XCTAssertTrue(ingestion.isUnconfirmed)

    let version6URL = try XCTUnwrap(
      Bundle(for: type(of: self)).url(forResource: "Backup v6 Inventory", withExtension: "json"))
    let version6 = try XCTUnwrap(JournalBackup.read(Data(contentsOf: version6URL)))
    try version6.restore(into: context)
    try context.save()
    let container = try XCTUnwrap(context.fetch(StockContainer.allRequest()).first)
    XCTAssertEqual(container.labReportID, UUID(uuidString: "39061EC4-D9E5-4A6D-9211-979600B9D72A"))
  }

  func testContainerCapacityRoundTripsAndOldBackupsKeepItUnknown() throws {
    let original = PersistenceController(inMemory: true).viewContext
    let container = StockContainer(context: original)
    container.name = "Bottle"
    container.unit = "mL"
    try Inventory.stage(.opening, quantity: 4, in: container)
    XCTAssertNil(container.capacityFraction)

    container.capacity = 10
    XCTAssertEqual(container.capacityFraction, 0.4)
    try Inventory.stage(.restock, quantity: 8, in: container)
    XCTAssertEqual(container.remaining, 12)
    XCTAssertNil(container.capacityFraction)
    try original.save()
    let backup = try JournalBackup(context: original, defaults: Self.emptyDefaults(), appVersion: "1")
    XCTAssertEqual(backup.formatVersion, JournalBackup.formatVersion)

    func restoredValues(from backup: JournalBackup) throws -> (capacity: Double?, remaining: Double, fraction: Double?) {
      let read = try XCTUnwrap(JournalBackup.read(backup.fileData()))
      let destination = PersistenceController(inMemory: true).viewContext
      try read.restore(into: destination)
      let restored = try XCTUnwrap(destination.fetch(StockContainer.allRequest()).first)
      return (restored.knownCapacity, restored.remaining, restored.capacityFraction)
    }

    let restored = try restoredValues(from: backup)
    XCTAssertEqual(restored.capacity, 10)
    XCTAssertEqual(restored.remaining, 12)
    XCTAssertNil(restored.fraction)

    var version3 = backup
    version3.formatVersion = 3
    version3.dataModel = "FreakLog Version 14"
    version3.entities["StockContainer"]?[0].attributes.removeValue(forKey: "capacity")
    let migrated = try restoredValues(from: version3)
    XCTAssertNil(migrated.capacity)
    XCTAssertEqual(migrated.remaining, 12)
    XCTAssertNil(migrated.fraction)
  }

  func testWrappedVersion1BackupsUpgradeBeforeCompletenessValidation() throws {
    var backup = try XCTUnwrap(JournalBackup.read(Self.version2Fixture))
    backup.formatVersion = 1
    backup.dataModel = "PW Version 12"
    backup.entities["ExperienceLocation"]?[0].attributes.removeValue(forKey: "hasExplicitLatitude")
    backup.entities["ExperienceLocation"]?[0].attributes.removeValue(forKey: "hasExplicitLongitude")
    backup.entities["WebhookMessage"]?[0].attributes.removeValue(forKey: "destinationURL")

    let upgraded = try XCTUnwrap(JournalBackup.read(backup.fileData()))
    XCTAssertEqual(upgraded.formatVersion, JournalBackup.formatVersion)
    let context = PersistenceController(inMemory: true).viewContext
    try upgraded.restore(into: context)
    try context.save()

    let location = try XCTUnwrap(context.fetch(ExperienceLocation.fetchRequest()).first)
    XCTAssertNil(location.latitudeUnwrapped)
    XCTAssertNil(location.longitudeUnwrapped)
    XCTAssertNil(try context.fetch(WebhookMessage.fetchRequest()).first?.destinationURL)

    backup.entities["ExperienceLocation"]?[0].attributes.removeValue(forKey: "latitude")
    let incomplete = try XCTUnwrap(JournalBackup.read(backup.fileData()))
    XCTAssertThrowsError(try incomplete.restore(into: context)) { error in
      XCTAssertEqual(error as? JournalBackupError, .missingProperty(entity: "ExperienceLocation", name: "latitude"))
    }
    XCTAssertFalse(context.hasChanges)
  }

  // Anything in the journal comes back the same: an export of the restored journal equals the first one,
  // apart from the ids the backup gives its objects
  func testRestoresEverythingExactly() throws {
    let source = PersistenceController(inMemory: true).viewContext
    try Self.fillEveryEntity(in: source)
    let backup = try JournalBackup(context: source, defaults: Self.emptyDefaults(), appVersion: "1")
    let model = try XCTUnwrap(source.persistentStoreCoordinator?.managedObjectModel)
    XCTAssertEqual(Set(backup.entities.keys), Set(model.entitiesByName.keys).subtracting(JournalBackup.localOperationEntities))
    XCTAssertTrue(backup.entities.values.allSatisfy { !$0.isEmpty }, "every entity has an object to compare")

    let read = try XCTUnwrap(JournalBackup.read(backup.fileData()))
    let target = PersistenceController(inMemory: true).viewContext
    try read.restore(into: target)
    try target.save()
    let restored = try JournalBackup(context: target, defaults: Self.emptyDefaults(), appVersion: "1")

    XCTAssertEqual(Self.canonical(restored), Self.canonical(backup))
  }

  func testLocalOperationRecordsStayInTheStoreDuringBackupRestore() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let receipt = NSEntityDescription.insertNewObject(forEntityName: "WatchLogReceipt", into: context)
    receipt.setValue(UUID(), forKey: "requestID")
    let deletion = NSEntityDescription.insertNewObject(forEntityName: "WebhookDeletion", into: context)
    deletion.setValue("123", forKey: "messageId")
    try context.save()

    let backup = try JournalBackup(context: context, defaults: Self.emptyDefaults(), appVersion: "1")
    XCTAssertNil(backup.entities["WatchLogReceipt"])
    XCTAssertNil(backup.entities["WebhookDeletion"])
    try backup.restore(into: context)
    try context.save()
    XCTAssertFalse(receipt.isDeleted)
    XCTAssertEqual(deletion.value(forKey: "messageId") as? String, "123")
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
    XCTAssertNil(BackupDate.date(from: "Z"))
    XCTAssertNil(BackupDate.date(from: "2023-11-14T22:13:20.Z"))
  }

  func testRefusesBackupsOfNewerVersions() {
    let data = Data(#"{"format": "FreakLog Backup", "formatVersion": 99}"#.utf8)
    XCTAssertThrowsError(try JournalBackup.read(data)) { error in
      XCTAssertEqual(error as? JournalBackupError, .newerFormat(99))
    }
  }

  func testOtherFilesAreNotBackups() throws {
    let journalFile = try JournalFile(experiences: [], customSubstances: [], customUnits: [])
    XCTAssertNil(try JournalBackup.read(JSONEncoder().encode(journalFile)))
    XCTAssertNil(try JournalBackup.read(Data("not json".utf8)))
  }

  func testBackupContainerFailsLegacyJSONParsingAndKeepsItsPayload() throws {
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

  private static let version2Fixture = Data(#"""
    FREAKLOG-BACKUP/1
    {
      "format": "FreakLog Backup",
      "formatVersion": 2,
      "dataModel": "PW Version 13",
      "appVersion": "1.4.3",
      "created": "2026-11-25T10:00:00.000000Z",
      "settings": {},
      "entities": {
        "CustomRoa": [], "CustomSubstance": [], "CustomUnit": [], "Experience": [],
        "ExperienceLocation": [{
          "id": "location-1",
          "attributes": {
            "name": "WGS 84", "latitude": 0, "longitude": 0,
            "hasExplicitLatitude": true, "hasExplicitLongitude": false
          },
          "relationships": {"ingestion": null, "legacyExperience": null}
        }],
        "Formulation": [], "FormulationComponent": [], "Ingestion": [], "ShulginRating": [],
        "Spray": [], "SubstanceCompanion": [], "SubstanceOverride": [], "TimedNote": [],
        "WebhookMessage": [{
          "id": "message-1",
          "attributes": {
            "id": null, "messageId": "123", "creationDate": null, "destinationURL": "https://example.com/hook"
          },
          "relationships": {"ingestion": null, "timedNote": null, "webhookPreset": null}
        }],
        "WebhookPreset": []
      }
    }
    """#.utf8)

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
    legacyLocation.hasExplicitLongitude = true
    experience.legacyLocation = legacyLocation

    let companion = SubstanceCompanion(context: context)
    companion.substanceName = "MDMA"
    companion.colorAsText = SubstanceColor.pink.rawValue
    companion.isHiddenInTimeline = true
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
    formulation.componentsSorted.first?.isHiddenInTimeline = true

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
    ingestion.isHiddenInTimeline = true
    ingestion.consumerName = "Alex"
    ingestion.note = "Line\nbreak and \"quotes\""
    ingestion.formulation = formulation
    ingestion.formulationAmount = 1.5
    ingestion.customUnit = unit
    ingestion.substanceCompanion = companion
    ingestion.experience = experience
    let routine = RoutineRecord(context: context)
    routine.id = UUID()
    routine.customUnit = unit
    let occurrence = RoutineOccurrence(context: context)
    occurrence.key = "morning"
    occurrence.scheduledAt = start
    occurrence.routine = routine
    ingestion.routineOccurrence = occurrence
    let container = StockContainer(context: context)
    container.name = "Home"
    container.unit = "units"
    container.formulation = formulation
    let change = StockChange(context: context)
    change.date = start
    change.kind = "use"
    change.quantity = -1.5
    change.container = container
    ingestion.stockChange = change
    let location = ExperienceLocation(context: context)
    location.name = "Home"
    location.latitude = 52.520008
    location.longitude = 13.404954
    ingestion.location = location

    let rating = ShulginRating(context: context)
    rating.option = ShulginRatingOption.threePlus.rawValue
    rating.creationDate = start
    rating.isHiddenInTimeline = true
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
      message.destinationURL = "https://example.com/hook"
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
