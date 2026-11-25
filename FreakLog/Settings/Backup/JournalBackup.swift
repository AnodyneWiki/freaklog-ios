import CoreData
import Foundation

// MARK: - JournalBackup

// A complete copy of the journal and its settings that restores exactly. Every entity and attribute
// of the data model is written as it is, so nothing is left out when the model grows, and relationships refer to the
// ids the backup gives its objects. JournalFile stays for the format the Android app reads, which leaves things out.
//
// Compatibility: a backup names its format version, and newer versions of the app read older backups by running the
// steps in `upgrades` on them first. When the data model or the settings written change, bump `formatVersion`, set
// `dataModelVersion`, add a step to fill in, remove or rename model keys as needed, and add a backup of the new
// version to the test fixtures. Fixtures are never edited,
// so every older version keeps importing.
struct JournalBackup: Codable {
  struct Record: Codable, Equatable {
    // Only refers to the object within this backup
    var id: String
    var attributes: [String: JSONValue]
    // A to-one relationship is an id or null, a to-many one a list of ids
    var relationships: [String: JSONValue]
  }

  static let format = "FreakLog Backup"
  private static let containerPrefix = Data("FREAKLOG-BACKUP/".utf8)
  private static let containerHeader = Data("FREAKLOG-BACKUP/1\n".utf8)
  static let formatVersion = 2
  // The data model this format version mirrors; a test fails once the current one differs
  static let dataModelVersion = "PW Version 12"

  // Settings that belong to the journal. Ones about this device (iCloud sync, the last unlock, the welcome screen,
  // migrations and the CloudKit schema) stay as they are.
  static let settingKeys = [
    PersistenceController.isEyeOpenKey2,
    PersistenceController.hasToUnlockAppKey,
    PersistenceController.lockTimeOptionKey,
    PersistenceController.hiddenTabsKey,
    PersistenceController.timeDisplayStyleKey,
    PersistenceController.isHidingDosageDotsKey,
    PersistenceController.isHidingToleranceChartInExperienceKey,
    PersistenceController.isHidingSubstanceInfoInExperienceKey,
    PersistenceController.areRedosesDrawnIndividuallyKey,
    PersistenceController.shouldAutomaticallyStartLiveActivityKey,
    PersistenceController.independentSubstanceHeightKey,
    PersistenceController.fabButtonPositionKey,
    PersistenceController.dynamicExperienceRangeHoursKey,
    PersistenceController.sendWebhooksEnabledKey,
    PersistenceController.webhookUsernameKey,
    PersistenceController.webhookTemplateKey,
    PersistenceController.webhookNoteTemplateKey,
    PersistenceController.webhookIsHyperlinkedKey,
    PersistenceController.webhookSubstanceInfoUrlKey,
    PersistenceController.isAnodyneAutoLoadEnabledKey,
    PersistenceController.doseSourceKey,
    PersistenceController.anodyneInstanceURLKey,
    PersistenceController.defaultJournalViewKey,
    PersistenceController.isHidingJournalTabSwitcherKey,
    PersistenceController.leaderboardServersKey,
    PersistenceController.leaderboardDeviceSeedKey,
    PersistenceController.isOpenLastExperienceSiriTipVisibleKey,
    PersistenceController.isSearchSubstanceSiriTipVisibleKey,
    PersistenceController.isAddIngestionSiriTipVisibleKey,
  ]

  // Steps that bring a backup of an older format version to the next one, keyed by the version they upgrade from.
  // They work on the raw JSON, so they can follow any change, e.g. renaming an attribute in every record:
  // `2: { backup in try JournalBackup.renameAttribute("old", to: "new", of: "Ingestion", in: &backup) }`
  static let upgrades: [Int: (inout JSONValue) throws -> Void] = [:]

  var format: String
  var formatVersion: Int
  var dataModel: String
  var appVersion: String
  // ISO 8601
  var created: String
  var settings: [String: JSONValue]
  // Records by entity name
  var entities: [String: [Record]]
  private var requiresCompleteRecords = true

  private enum CodingKeys: String, CodingKey {
    case format, formatVersion, dataModel, appVersion, created, settings, entities
  }
}

// MARK: - JournalBackupError

enum JournalBackupError: LocalizedError, Equatable {
  case invalidContainer
  case unrecognizedFormat
  case newerFormat(Int)
  case unsupportedFormat(Int)
  case unknownEntity(String)
  case missingEntity(String)
  case unknownProperty(entity: String, name: String)
  case missingProperty(entity: String, name: String)
  case invalidValue(entity: String, name: String)
  case unknownObject(String)
  case duplicateObject(String)

  var errorDescription: String? {
    switch self {
    case .invalidContainer:
      "This FreakLog backup file is damaged or uses an unsupported container."
    case .unrecognizedFormat:
      "This file format isn't supported by FreakLog."
    case .newerFormat:
      "This backup is from a newer version of FreakLog. Update the app to import it."
    case .unsupportedFormat(let version):
      "Backups of format version \(version) can't be read."
    case .unknownEntity(let name):
      "The backup contains unknown data (\(name))."
    case .missingEntity(let name):
      "The backup is incomplete and is missing \(name)."
    case .unknownProperty(let entity, let name):
      "The backup contains unknown data (\(entity).\(name))."
    case .missingProperty(let entity, let name):
      "The backup is incomplete and is missing \(entity).\(name)."
    case .invalidValue(let entity, let name):
      "The backup has an invalid value for \(entity).\(name)."
    case .unknownObject(let id), .duplicateObject(let id):
      "The backup refers to its objects inconsistently (\(id))."
    }
  }
}

// MARK: - Export

extension JournalBackup {
  // Reads everything in the context. Call it on the context's queue.
  init(
    context: NSManagedObjectContext,
    defaults: UserDefaults = .standard,
    appVersion: String,
    created: Date = .now)
    throws
  {
    let model = context.persistentStoreCoordinator?.managedObjectModel ?? NSManagedObjectModel()
    var objectsByEntity: [String: [NSManagedObject]] = [:]
    var ids: [NSManagedObjectID: String] = [:]
    for entity in model.entities {
      guard let name = entity.name else { continue }
      let request = NSFetchRequest<NSManagedObject>(entityName: name)
      request.includesSubentities = false
      let objects = try context.fetch(request).sorted {
        $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
      }
      objectsByEntity[name] = objects
      for object in objects {
        ids[object.objectID] = UUID().uuidString
      }
    }
    entities = try objectsByEntity.mapValues { objects in
      try objects.map { object in
        try Self.record(of: object, ids: ids)
      }
    }
    format = Self.format
    formatVersion = Self.formatVersion
    dataModel = Self.dataModelVersion
    self.appVersion = appVersion
    self.created = BackupDate.string(from: created)
    settings = Self.settingKeys.reduce(into: [:]) { settings, key in
      if let value = defaults.object(forKey: key) {
        settings[key] = JSONValue(propertyList: value)
      }
    }
    // An explicit null distinguishes an empty configuration from a version 1 backup.
    let profilesKey = PersistenceController.assistantProfilesKey
    settings[profilesKey] = defaults.data(forKey: profilesKey).map(JSONValue.init(propertyList:)) ?? .null
    if let activeProfile = defaults.string(forKey: PersistenceController.assistantActiveProfileKey) {
      settings[PersistenceController.assistantActiveProfileKey] = .string(activeProfile)
    }
  }

  // Pretty printed with sorted keys, so backups can be read and compared
  func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  // A non-JSON header keeps older journal importers from opening this as an empty journal.
  func fileData() throws -> Data {
    try Self.containerHeader + data()
  }

  private static func record(of object: NSManagedObject, ids: [NSManagedObjectID: String]) throws -> Record {
    let entity = object.entity
    var attributes: [String: JSONValue] = [:]
    for (name, attribute) in entity.attributesByName where !attribute.isTransient {
      attributes[name] = try json(object.value(forKey: name), of: attribute, entity: entity.name ?? "")
    }
    var relationships: [String: JSONValue] = [:]
    for (name, relationship) in entity.relationshipsByName where isWritten(relationship) {
      if relationship.isOrdered {
        let related = (object.value(forKey: name) as? NSOrderedSet)?.array as? [NSManagedObject] ?? []
        relationships[name] = .array(related.compactMap { ids[$0.objectID] }.map(JSONValue.string))
      } else if relationship.isToMany {
        let related = (object.value(forKey: name) as? Set<NSManagedObject>) ?? []
        relationships[name] = .array(related.compactMap { ids[$0.objectID] }.sorted().map(JSONValue.string))
      } else {
        let related = object.value(forKey: name) as? NSManagedObject
        relationships[name] = related.flatMap { ids[$0.objectID] }.map(JSONValue.string) ?? .null
      }
    }
    return Record(id: ids[object.objectID] ?? UUID().uuidString, attributes: attributes, relationships: relationships)
  }

  // One side of each relationship is enough: the to-one side, both sides of a one-to-one, and to-many relationships
  // only when their inverse is to-many too
  private static func isWritten(_ relationship: NSRelationshipDescription) -> Bool {
    !relationship.isToMany || relationship.inverseRelationship?.isToMany != false
  }

  private static func json(_ value: Any?, of attribute: NSAttributeDescription, entity: String) throws -> JSONValue {
    guard let value else { return .null }
    switch attribute.attributeType {
    case .stringAttributeType:
      guard let string = value as? String else { break }
      return .string(string)
    case .booleanAttributeType:
      guard let bool = value as? Bool else { break }
      return .bool(bool)
    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
      guard let number = value as? NSNumber else { break }
      return .number(Double(number.int64Value))
    case .doubleAttributeType, .floatAttributeType:
      guard let number = value as? NSNumber else { break }
      let double = number.doubleValue
      // JSON has no infinity or NaN
      return double.isFinite ? .number(double) : .string("\(double)")
    case .decimalAttributeType:
      guard let decimal = value as? NSDecimalNumber else { break }
      return .string(decimal.stringValue)
    case .dateAttributeType:
      guard let date = value as? Date else { break }
      return .string(BackupDate.string(from: date))
    case .UUIDAttributeType:
      guard let uuid = value as? UUID else { break }
      return .string(uuid.uuidString)
    case .URIAttributeType:
      guard let url = value as? URL else { break }
      return .string(url.absoluteString)
    case .binaryDataAttributeType:
      guard let data = value as? Data else { break }
      return .string(data.base64EncodedString())
    default:
      break
    }
    throw JournalBackupError.invalidValue(entity: entity, name: attribute.name)
  }
}

// MARK: - Import

extension JournalBackup {
  // The backup in the data, upgraded to the current format, or nil for other files such as a JournalFile
  static func read(_ data: Data) throws -> JournalBackup? {
    let wrapped = data.starts(with: containerPrefix)
    if wrapped, !data.starts(with: containerHeader) { throw JournalBackupError.invalidContainer }
    let payload = wrapped ? data.dropFirst(containerHeader.count) : data
    guard var json = try? JSONDecoder().decode(JSONValue.self, from: payload), let root = json.object else {
      if wrapped { throw JournalBackupError.invalidContainer }
      return nil
    }
    guard root["format"] != nil || root["formatVersion"] != nil || wrapped else { return nil }
    guard root["format"]?.string == format else { throw JournalBackupError.unrecognizedFormat }
    guard let version = json.object?["formatVersion"]?.number.flatMap({ Int(exactly: $0) }) else {
      throw JournalBackupError.unsupportedFormat(0)
    }
    guard version <= formatVersion else { throw JournalBackupError.newerFormat(version) }
    guard version >= 1 else { throw JournalBackupError.unsupportedFormat(version) }
    for step in version ..< formatVersion {
      try upgrades[step]?(&json)
      json = try replacing("formatVersion", with: .number(Double(step + 1)), in: json)
    }
    var backup = try JSONDecoder().decode(JournalBackup.self, from: JSONEncoder().encode(json))
    // Original v1 JSON backups can omit optional properties and use the model's defaults.
    backup.requiresCompleteRecords = wrapped
    return backup
  }

  // For upgrade steps: renames an attribute in every record of the entity
  static func renameAttribute(_ old: String, to new: String, of entity: String, in backup: inout JSONValue) throws {
    guard case .object(var root) = backup, case .object(var entities) = root["entities"] else { return }
    guard case .array(let records) = entities[entity] else { return }
    entities[entity] = .array(records.map { record in
      guard
        case .object(var fields) = record,
        case .object(var attributes) = fields["attributes"],
        let value = attributes.removeValue(forKey: old)
      else { return record }
      attributes[new] = value
      fields["attributes"] = .object(attributes)
      return .object(fields)
    })
    root["entities"] = .object(entities)
    backup = .object(root)
  }

  // Replaces everything in the context with the backup's objects. Nothing is changed for good until the caller saves,
  // so on an error the context can be thrown away with the journal untouched.
  func restore(into context: NSManagedObjectContext) throws {
    let model = context.persistentStoreCoordinator?.managedObjectModel ?? NSManagedObjectModel()
    try validateCompleteness(in: model)
    for entity in model.entities {
      guard let name = entity.name else { continue }
      let request = NSFetchRequest<NSManagedObject>(entityName: name)
      request.includesPropertyValues = false
      request.includesSubentities = false
      try context.fetch(request).forEach(context.delete)
    }
    var objects: [String: NSManagedObject] = [:]
    for (entityName, records) in entities {
      guard let entity = model.entitiesByName[entityName] else { throw JournalBackupError.unknownEntity(entityName) }
      for record in records {
        guard objects[record.id] == nil else { throw JournalBackupError.duplicateObject(record.id) }
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        objects[record.id] = object
        for (name, json) in record.attributes {
          guard let attribute = entity.attributesByName[name] else {
            throw JournalBackupError.unknownProperty(entity: entityName, name: name)
          }
          try object.setValue(Self.value(json, for: attribute, entity: entityName), forKey: name)
        }
      }
    }
    for (entityName, records) in entities {
      guard let entity = model.entitiesByName[entityName] else { continue }
      for record in records {
        guard let object = objects[record.id] else { continue }
        for (name, json) in record.relationships {
          guard let relationship = entity.relationshipsByName[name] else {
            throw JournalBackupError.unknownProperty(entity: entityName, name: name)
          }
          let related = { (id: JSONValue) throws -> NSManagedObject in
            guard
              let id = id.string,
              let related = objects[id],
              related.entity.name == relationship.destinationEntity?.name
            else { throw JournalBackupError.unknownObject(id.string ?? "\(id)") }
            return related
          }
          switch json {
          case .null where !relationship.isToMany:
            object.setValue(nil, forKey: name)
          case .string where !relationship.isToMany:
            try object.setValue(related(json), forKey: name)
          case .array(let ids) where relationship.isToMany:
            let relatedObjects = try ids.map(related)
            if relationship.isOrdered {
              object.setValue(NSOrderedSet(array: relatedObjects), forKey: name)
            } else {
              object.setValue(NSSet(array: relatedObjects), forKey: name)
            }
          default:
            throw JournalBackupError.invalidValue(entity: entityName, name: name)
          }
        }
      }
    }
  }

  private func validateCompleteness(in model: NSManagedObjectModel) throws {
    for (name, entity) in model.entitiesByName {
      guard let records = entities[name] else { throw JournalBackupError.missingEntity(name) }
      guard requiresCompleteRecords else { continue }
      let attributes = Set(entity.attributesByName.values.filter { !$0.isTransient }.map(\.name))
      let relationships = Set(entity.relationshipsByName.values.filter(Self.isWritten).map(\.name))
      for record in records {
        if let key = attributes.subtracting(record.attributes.keys).sorted().first
          ?? relationships.subtracting(record.relationships.keys).sorted().first {
          throw JournalBackupError.missingProperty(entity: name, name: key)
        }
      }
    }
  }

  // Replaces the journal's settings with the backup's; ones the backup doesn't have go back to their defaults
  func restoreSettings(to defaults: UserDefaults = .standard) {
    for key in Self.settingKeys {
      if let value = settings[key]?.propertyList {
        defaults.set(value, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    if let profiles = settings[PersistenceController.assistantProfilesKey] {
      AssistantProfileStore.restore(
        profilesFrom: profiles.propertyList as? Data,
        activeID: settings[PersistenceController.assistantActiveProfileKey]?.string,
        to: defaults)
    }
  }

  private static func replacing(_ key: String, with value: JSONValue, in json: JSONValue) throws -> JSONValue {
    guard case .object(var root) = json else { throw JournalBackupError.unsupportedFormat(0) }
    root[key] = value
    return .object(root)
  }

  private static func value(_ json: JSONValue, for attribute: NSAttributeDescription, entity: String) throws -> Any? {
    if json == .null {
      return nil
    }
    let invalid = JournalBackupError.invalidValue(entity: entity, name: attribute.name)
    switch attribute.attributeType {
    case .stringAttributeType:
      guard let string = json.string else { throw invalid }
      return string
    case .booleanAttributeType:
      guard let bool = json.bool else { throw invalid }
      return bool
    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
      guard let number = json.number, let integer = Int64(exactly: number) else { throw invalid }
      return NSNumber(value: integer)
    case .doubleAttributeType, .floatAttributeType:
      if let number = json.number {
        return NSNumber(value: number)
      }
      guard let text = json.string, let number = Double(text), !number.isFinite else { throw invalid }
      return NSNumber(value: number)
    case .decimalAttributeType:
      guard let text = json.string else { throw invalid }
      return NSDecimalNumber(string: text)
    case .dateAttributeType:
      guard let text = json.string, let date = BackupDate.date(from: text) else { throw invalid }
      return date
    case .UUIDAttributeType:
      guard let text = json.string, let uuid = UUID(uuidString: text) else { throw invalid }
      return uuid
    case .URIAttributeType:
      guard let text = json.string, let url = URL(string: text) else { throw invalid }
      return url
    case .binaryDataAttributeType:
      guard let text = json.string, let data = Data(base64Encoded: text) else { throw invalid }
      return data
    default:
      throw invalid
    }
  }
}

// MARK: - BackupDate

// ISO 8601 in UTC with microseconds, e.g. 2026-11-24T08:41:56.123456Z. Reading also takes fewer or more digits.
enum BackupDate {
  static func string(from date: Date) -> String {
    var seconds = date.timeIntervalSince1970.rounded(.down)
    var microseconds = Int(((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded())
    if microseconds == 1_000_000 {
      seconds += 1
      microseconds = 0
    }
    let base = String(formatter.string(from: Date(timeIntervalSince1970: seconds)).dropLast()) // without the "Z"
    return base + String(format: ".%06ldZ", microseconds)
  }

  static func date(from string: String) -> Date? {
    guard string.hasSuffix("Z") else { return nil }
    let parts = string.dropLast().split(separator: ".", maxSplits: 1)
    guard let base = formatter.date(from: String(parts[0]) + "Z") else { return nil }
    guard parts.count == 2 else { return base }
    let digits = parts[1]
    guard
      !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
      let fraction = Double("0." + digits)
    else { return nil }
    return base.addingTimeInterval(fraction)
  }

  // ISO8601DateFormatter is thread safe
  nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}

// MARK: - Settings values

extension JSONValue {
  // Data, which JSON can't hold, is written as {"base64": "…"}
  init(propertyList value: Any) {
    switch value {
    case let data as Data:
      self = .object(["base64": .string(data.base64EncodedString())])
    case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
      self = .bool(number.boolValue)
    case let number as NSNumber:
      self = .number(number.doubleValue)
    case let string as String:
      self = .string(string)
    case let date as Date:
      self = .string(BackupDate.string(from: date))
    case let array as [Any]:
      self = .array(array.map(JSONValue.init(propertyList:)))
    case let dictionary as [String: Any]:
      self = .object(dictionary.mapValues(JSONValue.init(propertyList:)))
    default:
      self = .null
    }
  }

  // Whole numbers come back as Int, as the settings that hold them read them
  var propertyList: Any? {
    switch self {
    case .null:
      return nil
    case .bool(let bool):
      return bool
    case .number(let number):
      if let integer = Int(exactly: number) {
        return integer
      }
      return number
    case .string(let string):
      return string
    case .array(let array):
      return array.compactMap(\.propertyList)
    case .object(let object):
      if object.count == 1, let base64 = object["base64"]?.string, let data = Data(base64Encoded: base64) {
        return data
      }
      return object.compactMapValues(\.propertyList)
    }
  }
}
