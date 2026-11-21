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
}

extension PersistenceController {
  // What to show for a stored substance name
  func displayName(for substanceName: String) -> String {
    overrideCache.entry(for: substanceName)?.displayName ?? substanceName
  }

  // The user's categories if they set any, else PsychonautWiki's
  func categories(for substanceName: String) -> [String] {
    overrideCache.entry(for: substanceName)?.categories
      ?? SubstanceRepo.shared.getSubstance(name: substanceName)?.categories
      ?? []
  }

  func getSubstanceOverride(for substanceName: String) -> SubstanceOverride? {
    let r = SubstanceOverride.fetchRequest()
    r.predicate = NSPredicate(format: "substanceName == %@", substanceName)
    r.fetchLimit = 1
    return (try? viewContext.fetch(r))?.first
  }

  static func substanceOverridesRequest() -> NSFetchRequest<SubstanceOverride> {
    let r = SubstanceOverride.fetchRequest()
    r.sortDescriptors = [NSSortDescriptor(keyPath: \SubstanceOverride.substanceName, ascending: true)]
    return r
  }

  // Stores the overrides, dropping a display name equal to the stored name and the row once nothing is left
  func setSubstanceOverride(for substanceName: String, displayName: String?, categories: [String]?) {
    let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = trimmedName.isEmpty || trimmedName == substanceName ? nil : trimmedName
    let existing = getSubstanceOverride(for: substanceName)
    if name == nil, categories == nil {
      if let existing {
        viewContext.delete(existing)
      }
    } else {
      let override = existing ?? SubstanceOverride(context: viewContext)
      override.substanceName = substanceName
      override.displayName = name
      override.categoryList = categories
    }
    saveViewContext()
  }
}

// In-memory copy of all overrides, read from views and the interaction checker on every lookup.
// Dropped whenever an override changes, together with the interaction checker's results.
final class SubstanceOverrideCache: @unchecked Sendable {
  struct Entry {
    let displayName: String?
    let categories: [String]?
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
        result[name] = Entry(displayName: override.trimmedDisplayName, categories: override.categoryList)
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
