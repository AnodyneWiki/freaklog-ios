import CoreData

// A user's changes to how a substance is shown and classified, keyed by the name its data is stored under.
// The display name only changes what is shown, so ingestions, colors, units and dose data keep matching.
// Categories replace the PsychonautWiki ones, or give a custom substance some; nil keeps the default.
extension SubstanceOverride {
  var categoryList: [String]? {
    get { categories.map { $0.isEmpty ? [] : $0.components(separatedBy: ",") } }
    set { categories = newValue?.joined(separator: ",") }
  }

  var trimmedDisplayName: String? {
    let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  var entry: SubstanceOverrideCache.Entry {
    SubstanceOverrideCache.Entry(displayName: trimmedDisplayName, categories: categoryList, tags: personalTags)
  }

  var personalTags: PersonalSubstanceTags {
    get {
      guard let data = personalTagsJSON?.data(using: .utf8),
            let value = try? JSONDecoder().decode(PersonalSubstanceTags.self, from: data)
      else { return PersonalSubstanceTags() }
      return value
    }
    set {
      personalTagsJSON = newValue.names.isEmpty
        ? nil
        : (try? JSONEncoder().encode(newValue)).map { String(decoding: $0, as: UTF8.self) }
    }
  }
}

struct PersonalSubstanceTags: Codable, Equatable {
  let names: [String]
  let primary: String?

  init(_ names: [String] = [], primary: String? = nil) {
    var seen = Set<String>()
    self.names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert(Self.key($0)).inserted }
    self.primary = self.names.first { Self.key($0) == primary.map(Self.key) }
  }

  private enum CodingKeys: String, CodingKey { case names, primary }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(values.decode([String].self, forKey: .names), primary: values.decodeIfPresent(String.self, forKey: .primary))
  }

  static func key(_ name: String) -> String {
    name.precomposedStringWithCanonicalMapping.lowercased()
  }

  func contains(_ tag: String) -> Bool {
    names.contains { Self.key($0) == Self.key(tag) }
  }

  func merged(_ other: Self) -> Self {
    Self((names + other.names).sorted(), primary: [primary, other.primary].compactMap { $0 }.max())
  }
}

extension Substance {
  var displayName: String {
    PersistenceController.shared.displayName(for: name)
  }
}

extension Ingestion {
  var substanceDisplayName: String {
    PersistenceController.shared.displayName(for: substanceNameUnwrapped)
  }
}

extension CustomUnit {
  var substanceDisplayName: String {
    PersistenceController.shared.displayName(for: substanceNameUnwrapped)
  }
}

extension PersistenceController {
  // What to show for a stored substance name
  func displayName(for substanceName: String) -> String {
    overrideCache.entry(for: substanceName)?.displayName ?? substanceName
  }

  // Stored names whose display name contains the text, for searches that query stored names
  func substanceNames(withDisplayNameContaining text: String) -> [String] {
    overrideCache.storedNames { $0.localizedStandardContains(text) }
  }

  // The user's categories if they set any, else PsychonautWiki's
  func categories(for substanceName: String) -> [String] {
    overrideCache.entry(for: substanceName)?.categories
      ?? SubstanceRepo.shared.getSubstance(name: substanceName)?.categories
      ?? []
  }

  // The substance's drug class for leaderboards, e.g. "stimulant" rather than "common"
  func primaryCategory(for substanceName: String) -> String? {
    Self.primaryCategory(of: categories(for: substanceName))
  }

  // Tags that say something about a substance but not what kind of drug it is
  private static let categoryTags: Set = ["common", "habit-forming", "research-chemical", "tentative"]

  // The first category that is not a tag, else the first category
  static func primaryCategory(of categories: [String]) -> String? {
    categories.first { !categoryTags.contains($0) } ?? categories.first
  }

  // The user's display name and categories for the substance, merged over all its rows
  func substanceOverride(for substanceName: String) -> SubstanceOverrideCache.Entry? {
    overrideCache.entry(for: substanceName)
  }

  func personalTags(for substanceName: String) -> PersonalSubstanceTags {
    substanceOverride(for: substanceName)?.tags ?? PersonalSubstanceTags()
  }

  @MainActor
  func setPersonalTags(_ tags: PersonalSubstanceTags, for substanceName: String) throws {
    let context = try journalEditContext()
    let existing = try context.fetch(Self.substanceOverridesRequest(for: substanceName))
    let entry = existing.reduce(SubstanceOverrideCache.Entry(displayName: nil, categories: nil)) { $0.merged($1.entry) }
    Self.applySubstanceOverride(
      .init(displayName: entry.displayName, categories: entry.categories, tags: tags),
      for: substanceName,
      existing: existing,
      in: context
    )
    try context.save()
  }

  static func substanceOverridesRequest() -> NSFetchRequest<SubstanceOverride> {
    let r = SubstanceOverride.fetchRequest()
    r.sortDescriptors = [NSSortDescriptor(keyPath: \SubstanceOverride.substanceName, ascending: true)]
    return r
  }

  // All rows of one substance; iCloud can bring one from each device
  static func substanceOverridesRequest(for substanceName: String) -> NSFetchRequest<SubstanceOverride> {
    let r = substanceOverridesRequest()
    r.predicate = NSPredicate(format: "substanceName == %@", substanceName)
    return r
  }

  // Stores the overrides, dropping a display name equal to the stored name and the row once nothing is left.
  // Duplicate rows from iCloud collapse into the first one.
  func setSubstanceOverride(for substanceName: String, displayName: String?, categories: [String]?) {
    let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = trimmedName.isEmpty || trimmedName == substanceName ? nil : trimmedName
    let existing = (try? viewContext.fetch(Self.substanceOverridesRequest(for: substanceName))) ?? []
    let tags = existing.dropFirst().reduce(existing.first?.personalTags ?? PersonalSubstanceTags()) {
      $0.merged($1.personalTags)
    }
    Self.applySubstanceOverride(
      .init(displayName: name, categories: categories, tags: tags),
      for: substanceName,
      existing: existing,
      in: viewContext
    )
    saveViewContext()
  }

  static func applySubstanceOverride(
    _ entry: SubstanceOverrideCache.Entry,
    for substanceName: String,
    existing: [SubstanceOverride],
    in context: NSManagedObjectContext
  ) {
    let isEmpty = entry.displayName == nil && entry.categories == nil && entry.tags.names.isEmpty
    for row in existing.dropFirst(isEmpty ? 0 : 1) {
      context.delete(row)
    }
    if !isEmpty {
      let override = existing.first ?? SubstanceOverride(context: context)
      override.substanceName = substanceName
      override.displayName = entry.displayName
      override.categoryList = entry.categories
      override.personalTags = entry.tags
    }
  }
}

// In-memory copy of all overrides, read from views and the interaction checker on every lookup.
// Dropped whenever an override changes, together with the interaction checker's results.
final class SubstanceOverrideCache: @unchecked Sendable {
  struct Entry: Equatable {
    let displayName: String?
    let categories: [String]?
    let tags: PersonalSubstanceTags

    init(displayName: String?, categories: [String]?, tags: PersonalSubstanceTags = PersonalSubstanceTags()) {
      self.displayName = displayName
      self.categories = categories
      self.tags = tags
    }

    // Combines two rows of one substance, e.g. made on two devices before iCloud synced them. Only the values
    // decide, because object IDs differ between devices, so every device keeps the same one: the greatest
    // display name, and the categories whose joined text is greatest (so a non-empty list beats an empty one).
    func merged(_ other: Entry) -> Entry {
      let categoryLists = [categories, other.categories].compactMap { $0 }
      return Entry(
        displayName: [displayName, other.displayName].compactMap { $0 }.max(),
        categories: categoryLists.max { $0.joined(separator: ",") < $1.joined(separator: ",") },
        tags: tags.merged(other.tags)
      )
    }
  }

  private let context: NSManagedObjectContext
  private let lock = NSLock()
  private var entries: [String: Entry]?
  private var observer: NSObjectProtocol?

  init(context: NSManagedObjectContext) {
    self.context = context
    observer = NotificationCenter.default.addObserver(
      forName: .NSManagedObjectContextObjectsDidChange,
      object: context,
      queue: nil
    ) { [weak self] notification in
      guard Self.affectsOverrides(notification) else { return }
      self?.invalidate()
    }
  }

  func entry(for substanceName: String) -> Entry? {
    lock.lock()
    defer { lock.unlock() }
    if entries == nil {
      entries = load()
    }
    return entries?[substanceName]
  }

  func storedNames(whereDisplayName isMatch: (String) -> Bool) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    if entries == nil {
      entries = load()
    }
    return entries?.compactMap { name, entry in
      entry.displayName.map(isMatch) == true ? name : nil
    } ?? []
  }

  private func invalidate() {
    lock.lock()
    entries = nil
    lock.unlock()
    InteractionChecker.clearCache()
  }

  private func load() -> [String: Entry] {
    var result: [String: Entry] = [:]
    context.performAndWait {
      let overrides = (try? context.fetch(SubstanceOverride.fetchRequest())) ?? []
      for override in overrides {
        guard let name = override.substanceName else { continue }
        let entry = override.entry
        result[name] = result[name].map { $0.merged(entry) } ?? entry
      }
    }
    return result
  }

  private static func affectsOverrides(_ notification: Notification) -> Bool {
    let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
    return keys.contains { key in
      (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is SubstanceOverride } ?? false
    } || notification.userInfo?[NSInvalidatedAllObjectsKey] != nil
  }
}
