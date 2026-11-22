import Foundation

// AnodyneWiki's doses and timings, used where PsychonautWiki and the user have none. Doses come from its dose
// tiers per route. For timings, its users note the onset, come-up and duration of the routes they took, which
// are combined per route (earliest to latest); otherwise the substance's duration of action, e.g.
// "3 – 6 hours", is used as the total for every route.
//
// Only data AnodyneClient has already cached is used, so looking something up never goes online. That keeps
// it cheap and synchronous for the dose and duration resolver, which every timeline and dose display uses.
final class AnodyneFallbackStore: @unchecked Sendable {
  static let shared = AnodyneFallbackStore()

  private let lock = NSLock()
  private var didLoadCache = false
  // Lowercased name or title -> lowercased AnodyneWiki title
  private var titlesByName: [String: String] = [:]
  // By lowercased title
  private var totals: [String: RoaDuration] = [:]
  private var doses: [String: [AdministrationRoute: RoaDose]] = [:]
  // Users' timings by the lowercased name their note uses, which may be a title, abbreviation or other name
  private var noteRoutes: [String: [AdministrationRoute: [AnodyneUserNote.Route]]] = [:]
  // The timings combined by lowercased title, built from `noteRoutes` once they are asked for
  private var builtRouteDurations: [String: [AdministrationRoute: RoaDuration]]?

  func dose(for substanceName: String, route: AdministrationRoute) -> RoaDose? {
    lock.lock()
    defer { lock.unlock() }
    loadCacheIfNeeded()
    return doses[title(for: substanceName)]?[route]
  }

  func duration(for substanceName: String, route: AdministrationRoute) -> RoaDuration? {
    lock.lock()
    defer { lock.unlock() }
    loadCacheIfNeeded()
    let title = title(for: substanceName)
    return routeDurations()[title]?[route] ?? totals[title]
  }

  private func title(for substanceName: String) -> String {
    titlesByName[substanceName.lowercased()] ?? substanceName.lowercased()
  }

  // The routes with AnodyneWiki dose tiers or users' timings
  func routesWithData(for substanceName: String) -> [AdministrationRoute] {
    lock.lock()
    defer { lock.unlock() }
    loadCacheIfNeeded()
    let title = title(for: substanceName)
    let durations = routeDurations()[title]
    return AdministrationRoute.allCases.filter { doses[title]?[$0] != nil || durations?[$0] != nil }
  }

  // The routes users noted timings for; a duration of action applies to any route
  func routesWithTimings(for substanceName: String) -> [AdministrationRoute] {
    lock.lock()
    defer { lock.unlock() }
    loadCacheIfNeeded()
    let title = title(for: substanceName)
    let durations = routeDurations()[title]
    return AdministrationRoute.allCases.filter { durations?[$0] != nil }
  }

  // Notes name a substance by whichever alias their user chose, so their routes are grouped by title first.
  // Call with the lock held.
  private func routeDurations() -> [String: [AdministrationRoute: RoaDuration]] {
    if let builtRouteDurations {
      return builtRouteDurations
    }
    var routesByTitle: [String: [AdministrationRoute: [AnodyneUserNote.Route]]] = [:]
    for (name, byRoute) in noteRoutes {
      routesByTitle[title(for: name), default: [:]].merge(byRoute, uniquingKeysWith: +)
    }
    let built = routesByTitle.mapValues { byRoute in
      byRoute.compactMapValues(AnodyneTiming.combinedDuration)
    }
    builtRouteDurations = built
    return built
  }

  func record(_ substance: AnodyneSubstance, lookedUpAs name: String) {
    lock.lock()
    defer { lock.unlock() }
    recordUnlocked(substance, lookedUpAs: name)
  }

  func record(_ notes: [AnodyneUserNote]) {
    lock.lock()
    defer { lock.unlock() }
    recordUnlocked(notes)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    titlesByName = [:]
    totals = [:]
    doses = [:]
    noteRoutes = [:]
    builtRouteDurations = nil
    didLoadCache = true
  }

  private func recordUnlocked(_ substance: AnodyneSubstance, lookedUpAs name: String) {
    let title = substance.title.lowercased()
    for alias in [name, substance.title] + substance.abbreviations {
      titlesByName[alias.lowercased()] = title
    }
    if let total = substance.durationOfAction.flatMap(AnodyneTiming.range(in:)) {
      totals[title] = RoaDuration(onset: nil, comeup: nil, peak: nil, offset: nil, total: total, afterglow: nil)
    }
    // The first dose tiers of each route the app knows
    var routeDoses: [AdministrationRoute: RoaDose] = [:]
    for dosing in substance.dosing {
      guard let route = dosing.route, routeDoses[route] == nil, let roaDose = dosing.roaDose else { continue }
      routeDoses[route] = roaDose
    }
    doses[title] = routeDoses
    // New aliases can group notes differently
    builtRouteDurations = nil
  }

  private func recordUnlocked(_ notes: [AnodyneUserNote]) {
    var routes: [String: [AdministrationRoute: [AnodyneUserNote.Route]]] = [:]
    for note in notes {
      for route in note.routes {
        guard let administrationRoute = AnodyneSubstance.route(forMethod: route.name) else { continue }
        routes[note.substanceName.lowercased(), default: [:]][administrationRoute, default: []].append(route)
      }
    }
    noteRoutes = routes
    builtRouteDurations = nil
  }

  // After a relaunch the cache on disk has what was loaded before
  private func loadCacheIfNeeded() {
    guard !didLoadCache else { return }
    didLoadCache = true
    for (name, substance) in AnodyneClient.cachedSubstancesOnDisk() {
      recordUnlocked(substance, lookedUpAs: name)
    }
    recordUnlocked(AnodyneClient.cachedUserNotesOnDisk())
  }
}

enum AnodyneTiming {
  // The first time or time range in a text such as "3 – 6 hours", "~ 7-8 h", "10-15 seconds" or
  // "Immediate release dosing: 3 – 6 hours Extended release dosing: 8 – 12 hours" (the first is used)
  static func range(in text: String) -> DurationRange? {
    let pattern = "(\\d+(?:[.,]\\d+)?)\\s*(?:(?:–|-|to)\\s*(\\d+(?:[.,]\\d+)?))?\\s*"
      + "(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d)\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let lowRange = Range(match.range(at: 1), in: text),
          let unitRange = Range(match.range(at: 3), in: text),
          let low = Double(text[lowRange].replacingOccurrences(of: ",", with: "."))
    else { return nil }
    let high = Range(match.range(at: 2), in: text)
      .flatMap { Double(text[$0].replacingOccurrences(of: ",", with: ".")) } ?? low
    let units: DurationRange.Units = switch text[unitRange].lowercased().first {
    case "s": .seconds
    case "m": .minutes
    case "d": .days
    default: .hours
    }
    return DurationRange(min: min(low, high), max: max(low, high), units: units)
  }

  // Several users' timings of one route, from the earliest to the latest any of them noted
  static func combinedDuration(_ routes: [AnodyneUserNote.Route]) -> RoaDuration? {
    func combined(_ value: (AnodyneUserNote.Route) -> String?) -> DurationRange? {
      let ranges = routes.compactMap(value).compactMap(range(in:))
      guard let low = ranges.compactMap(\.minSec).min(), let high = ranges.compactMap(\.maxSec).max() else {
        return nil
      }
      return readableRange(fromSeconds: low, to: high)
    }
    let onset = combined(\.onset)
    let comeup = combined(\.comeup)
    let total = combined(\.duration)
    guard onset != nil || comeup != nil || total != nil else { return nil }
    return RoaDuration(onset: onset, comeup: comeup, peak: nil, offset: nil, total: total, afterglow: nil)
  }

  // In the largest unit both ends are at least 2 of, so the timeline's chips stay short
  private static func readableRange(fromSeconds low: Double, to high: Double) -> DurationRange {
    let units: [(DurationRange.Units, Double)] = [(.hours, 3600), (.minutes, 60), (.seconds, 1)]
    let (unit, seconds) = units.first { low / $0.1 >= 2 || ($0.0 == .seconds) } ?? (.seconds, 1)
    func rounded(_ value: Double) -> Double {
      (value / seconds * 2).rounded() / 2
    }
    return DurationRange(min: rounded(low), max: rounded(high), units: unit)
  }
}
