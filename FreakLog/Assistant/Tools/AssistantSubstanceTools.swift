import CoreData
import Foundation

// Tools for substance facts: the bundled PsychonautWiki data and the user's own substances and overrides, the
// interaction checker, a tolerance estimate, what is still active, and AnodyneWiki
extension AssistantToolbox {
  func substanceTools() -> [Tool] {
    let progress = "Checking substance data…"
    return [
      Tool(
        name: "get_substance_info",
        description: "Look up a substance in the PsychonautWiki data bundled with the app, or the user's own custom substances: summary, dose ranges and durations per route (including the user's own changes), tolerance, cross-tolerances, toxicity, risks, safer-use tips and listed interactions. Takes common names and abbreviations.",
        parameters: [
          Parameter(
            name: "name",
            description: "Substance name, common name or abbreviation, e.g. 'MDMA' or 'Molly'.",
            kind: .string,
            isRequired: true),
        ],
        progress: progress,
        run: { [unowned self] arguments in substanceInfo(arguments.string("name")) }),
      Tool(
        name: "check_interactions",
        description: "Check every pair of the substances for known interactions (dangerous, unsafe, uncertain) with the app's interaction checker. Pairs without data are listed as no_data, which doesn't mean they are safe.",
        parameters: [
          Parameter(
            name: "substances",
            description: "Two to \(Self.maxInteractionSubstances) substance names as the app's data names them, e.g. 'Alcohol' (not 'ethanol'), 'MDMA'.",
            kind: .stringArray,
            isRequired: true),
        ],
        progress: progress,
        run: { [unowned self] arguments in checkInteractions(arguments.strings("substances")) }),
      Tool(
        name: "get_tolerance",
        description: "Estimate the user's tolerance to a substance from their last logged use of it and of cross-tolerant substances, with the time it is expected to be back at baseline.",
        parameters: [Parameter(name: "substance", description: "Substance name.", kind: .string, isRequired: true)],
        progress: progress,
        run: { [unowned self] arguments in try tolerance(arguments.string("substance")) }),
      Tool(
        name: "get_active_ingestions",
        description: "List the ingestions of the last N hours with the expected end of their effects, from each route's duration. Use it for 'what is still active?', and before talking about redosing or combining.",
        parameters: [Parameter(
          name: "hours_back",
          description: "How many hours to look back (default 24, at most 72).",
          kind: .integer)],
        progress: progress,
        run: { [unowned self] arguments in try activeIngestions(hoursBack: arguments.integer(
          "hours_back",
          default: 24,
          in: 1 ... 72)) }),
    ]
  }

  func anodyneTools() -> [Tool] {
    let progress = "Asking AnodyneWiki…"
    return [
      Tool(
        name: "search_anodyne_wiki",
        description: "Search the substance index of AnodyneWiki (a pharmacology and harm-reduction wiki) by name or abbreviation, to find the exact page title for lookup_anodyne_wiki.",
        parameters: [Parameter(name: "query", description: "Substance name or abbreviation.", kind: .string, isRequired: true)],
        progress: progress,
        run: { [unowned self] arguments in try await searchAnodyneWiki(arguments.string("query")) }),
      Tool(
        name: "lookup_anodyne_wiki",
        description: "Read a substance page and user annotations (user_notes from AnodyneWiki userpages) on AnodyneWiki: dose tiers per route from logged doses, duration, half-life, interactions, adverse effects, warnings, subjective effects, and individual contributors' dosages, route timings, effects, effect_groups, after-effects, tolerance and notes. Takes titles and common abbreviations. Call this when asked about subjective effects so user annotations are included; say when facts come from AnodyneWiki and attribute personal annotations to the contributor.",
        parameters: [Parameter(
          name: "substance",
          description: "Page title or abbreviation, e.g. 'MDMA' or 'Amphetamine'.",
          kind: .string,
          isRequired: true)],
        progress: progress,
        run: { [unowned self] arguments in try await lookUpAnodyneWiki(arguments.string("substance")) }),
    ]
  }

  // The name the app stores a substance under, from its name, a common name, an abbreviation or display name
  func storedSubstanceName(for query: String) -> String? {
    let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    func matches(_ other: String) -> Bool {
      other.caseInsensitiveCompare(name) == .orderedSame
    }
    let persistence = PersistenceController.shared
    if let custom = persistence.getAllCustomSubstances().first(where: { matches($0.nameUnwrapped) }) {
      return custom.nameUnwrapped
    }
    if
      let renamed = persistence.substanceNames(withDisplayNameContaining: name)
        .first(where: { matches(persistence.displayName(for: $0)) })
    {
      return renamed
    }
    let substances = SubstanceRepo.shared.substances
    if
      let substance = substances.first(where: { matches($0.name) }) ?? substances
        .first(where: { $0.commonNames.contains(where: matches) })
    {
      return substance.name
    }
    if let alias = Self.aliases[name.lowercased()], SubstanceRepo.shared.getSubstance(name: alias) != nil {
      return alias
    }
    return InteractionChecker.additionalInteractionsToCheck.first(where: matches)
  }

  // Everyday or chemical names models tend to use that the bundled data doesn't list
  private static let aliases = [
    "ethanol": "Alcohol",
    "ethyl alcohol": "Alcohol",
    "beer": "Alcohol",
    "wine": "Alcohol",
    "thc": "Cannabis",
    "weed": "Cannabis",
  ]
  private static let maxInteractionSubstances = 8

  // Cuts long texts and lists of a page down, so a page fits into a request
  private static func trimmed(_ value: JSONValue, textLimit: Int) -> JSONValue {
    switch value {
    case .string(let string): AssistantFormat.text(string.anodyneCleaned, limit: textLimit)
    case .array(let array): .array(array.prefix(30).map { trimmed($0, textLimit: textLimit) })
    case .object(let object): .object(object.mapValues { trimmed($0, textLimit: textLimit) })
    default: value
    }
  }

  private func substanceInfo(_ query: String) -> JSONValue {
    guard !query.isEmpty else { return Self.error("'name' is required.") }
    guard let name = storedSubstanceName(for: query) else {
      let similar = SubstanceRepo.shared.substances.map(\.name).filter { $0.localizedCaseInsensitiveContains(query) }.prefix(5)
      return Self.error(
        "There is no substance called '\(query)' in the app's data. Similar names: \(similar.isEmpty ? "none" : similar.joined(separator: ", "))."
          + (tool(named: "search_anodyne_wiki") == nil ? "" : " You can also try search_anodyne_wiki."))
    }
    let persistence = PersistenceController.shared
    if let custom = persistence.getCustomSubstance(name: name) {
      return Self.success([
        "name": .string(persistence.displayName(for: name)),
        "is_custom_substance": .bool(true),
        "source": "A custom substance the user added to the app",
        "description": AssistantFormat.optionalText(custom.explanationUnwrapped, limit: limits.maxTextCharacters),
        "units": .string(custom.unitsUnwrapped),
        "categories": AssistantFormat.strings(persistence.categories(for: name)),
        "routes": routesJSON(for: name),
      ])
    }
    guard let substance = SubstanceRepo.shared.getSubstance(name: name) else {
      // One of the interaction checker's extra names, such as SSRIs, which has no substance page
      return Self.success([
        "name": .string(name),
        "source": "The app's interaction checker",
        "note": "The app has no substance page for this, but check_interactions knows it.",
      ])
    }
    let limit = limits.maxTextCharacters
    return Self.success([
      "name": .string(persistence.displayName(for: name)),
      "source": .string(substance.usesWikiReferences
        ? "PsychonautWiki data bundled with the app, with the user's own dose and duration changes"
        : substance.referenceSource.title + " identity record"),
      "url": substance.url.map { .string($0.absoluteString) } ?? .null,
      "common_names": AssistantFormat.strings(Array(substance.commonNames.prefix(10))),
      "categories": AssistantFormat.strings(persistence.categories(for: name)),
      "summary": AssistantFormat.optionalText(substance.summary, limit: limit),
      "dosage_remark": AssistantFormat.optionalText(substance.dosageRemark, limit: limit),
      "tolerance": substance.tolerance.map { tolerance in
        .object([
          "full": tolerance.full.map { .string($0) } ?? .null,
          "half": tolerance.half.map { .string($0) } ?? .null,
          "zero": tolerance.zero.map { .string($0) } ?? .null,
        ])
      } ?? .null,
      "cross_tolerances": AssistantFormat.strings(substance.crossTolerances),
      "addiction_potential": AssistantFormat.optionalText(substance.addictionPotential, limit: limit),
      "toxicity": AssistantFormat.strings(substance.toxicities),
      "general_risks": AssistantFormat.optionalText(substance.generalRisks, limit: limit),
      "long_term_risks": AssistantFormat.optionalText(substance.longtermRisks, limit: limit),
      "safer_use": AssistantFormat.strings(substance.saferUse),
      "interactions": substance.interactions.map { interactions in
        .object([
          "dangerous": AssistantFormat.strings(interactions.dangerous),
          "unsafe": AssistantFormat.strings(interactions.unsafe),
          "uncertain": AssistantFormat.strings(interactions.uncertain),
        ])
      } ?? .null,
      "routes": routesJSON(for: name),
    ])
  }

  // Dose ranges and durations of every route the app has data for, as the app shows them
  private func routesJSON(for substanceName: String) -> JSONValue {
    .array(AdministrationRoute.allCases.compactMap { route in
      let roa = PersistenceController.shared.resolvedRoa(for: substanceName, route: route)
      guard roa.dose != nil || roa.duration != nil else { return nil }
      var json: [String: JSONValue] = ["route": .string(route.rawValue)]
      if let dose = roa.dose {
        json["dose_units"] = .string(dose.units)
        json["light_from"] = AssistantFormat.number(dose.lightMin)
        json["common_from"] = AssistantFormat.number(dose.commonMin)
        json["strong_from"] = AssistantFormat.number(dose.strongMin)
        json["heavy_from"] = AssistantFormat.number(dose.heavyMin)
      }
      if let duration = roa.duration {
        let phases = [
          ("onset", duration.onset), ("comeup", duration.comeup), ("peak", duration.peak),
          ("offset", duration.offset), ("total", duration.total), ("afterglow", duration.afterglow),
        ]
        for (key, range) in phases {
          if let text = range?.displayString {
            json[key] = .string(text)
          }
        }
      }
      return .object(json)
    })
  }

  private func checkInteractions(_ requested: [String]) -> JSONValue {
    let unrecognized = requested.filter { storedSubstanceName(for: $0) == nil }
    var names: [String] = []
    for name in requested.map({ storedSubstanceName(for: $0) ?? $0 })
      where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
    {
      names.append(name)
    }
    guard names.count >= 2 else { return Self.error("Give at least two different substances.") }
    guard names.count <= Self.maxInteractionSubstances else {
      return Self.error("Check at most \(Self.maxInteractionSubstances) substances at once.")
    }
    var found: [JSONValue] = []
    var noData: [JSONValue] = []
    for (index, name) in names.enumerated() {
      for other in names.dropFirst(index + 1) {
        if let type = InteractionChecker.getInteractionTypeBetween(aName: name, bName: other) {
          found.append(.object(["a": .string(name), "b": .string(other), "risk": .string(String(describing: type))]))
        } else {
          noData.append(.string("\(name) + \(other)"))
        }
      }
    }
    var result: [String: JSONValue] = [
      "substances": AssistantFormat.strings(names),
      "interactions": .array(found),
      "no_data": .array(noData),
      "note": "From the PsychonautWiki and TripSit interaction data and the user's categories. No data doesn't mean a combination is safe.",
    ]
    if !unrecognized.isEmpty {
      result["unrecognized_substances"] = AssistantFormat.strings(unrecognized)
      result["warning"] = .string(
        "The app's data doesn't know \(unrecognized.joined(separator: ", ")), so pairs with it couldn't be checked. Find the name the app uses with get_substance_info and check again; don't tell the user the combination has no known interactions.")
    }
    return Self.success(result)
  }

  private func tolerance(_ query: String) throws -> JSONValue {
    guard !query.isEmpty else { return Self.error("'substance' is required.") }
    let name = storedSubstanceName(for: query) ?? query
    let substance = SubstanceRepo.shared.getSubstance(name: name)
    let lastUse = try lastPersonalIngestion(of: [name])
    // Substances in a category this one is cross-tolerant with
    let crossTolerances = Set((substance?.crossTolerances ?? []).map { $0.lowercased() })
    let crossTolerant = SubstanceRepo.shared.substances
      .filter { $0.name != name && !crossTolerances.isDisjoint(with: PersistenceController.shared.categories(for: $0.name).map { $0.lowercased() }) }
      .map(\.name)
    let lastCrossTolerantUse = crossTolerant.isEmpty ? nil : try lastPersonalIngestion(of: crossTolerant)
    let mostRecent = [lastUse, lastCrossTolerantUse].compactMap { $0 }.max { $0.timeUnwrapped < $1.timeUnwrapped }
    var result: [String: JSONValue] = [
      "substance": .string(PersistenceController.shared.displayName(for: name)),
      "last_use": lastUse.map { .string(AssistantFormat.date($0.timeUnwrapped)) } ?? .null,
      "cross_tolerances": AssistantFormat.strings(substance?.crossTolerances ?? []),
      "tolerance_data": substance?.tolerance.map { tolerance in
        .object([
          "full": tolerance.full.map { .string($0) } ?? .null,
          "half": tolerance.half.map { .string($0) } ?? .null,
          "zero": tolerance.zero.map { .string($0) } ?? .null,
        ])
      } ?? .null,
      "note": "A rough estimate from logged ingestions and PsychonautWiki's tolerance times; tolerance differs between people.",
    ]
    if let lastCrossTolerantUse, lastCrossTolerantUse != lastUse {
      result["last_cross_tolerant_use"] = .object([
        "substance": .string(PersistenceController.shared.displayName(for: lastCrossTolerantUse.substanceNameUnwrapped)),
        "time": .string(AssistantFormat.date(lastCrossTolerantUse.timeUnwrapped)),
      ])
    }
    guard let mostRecent else {
      result["estimate"] = "no logged use, probably no tolerance from it"
      return Self.success(result)
    }
    let hoursSince = Date.now.timeIntervalSince(mostRecent.timeUnwrapped) / 3600
    let half = substance?.tolerance?.halfToleranceInHours
    let zero = substance?.tolerance?.zeroToleranceInHours
    result["hours_since_relevant_use"] = AssistantFormat.number(hoursSince)
    result["estimate"] = if let zero, hoursSince >= zero {
      "probably back at baseline"
    } else if let half, hoursSince >= half {
      "probably about half of full tolerance or less"
    } else if half != nil || zero != nil {
      "probably elevated"
    } else {
      "unknown, the app has no tolerance times for this substance"
    }
    if let zero {
      result["baseline_expected"] = .string(AssistantFormat.date(mostRecent.timeUnwrapped.addingTimeInterval(zero * 3600)))
    }
    return Self.success(result)
  }

  private func lastPersonalIngestion(of substanceNames: [String]) throws -> Ingestion? {
    let request = PersistenceController.personalIngestionsRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      request.predicate ?? NSPredicate(value: true),
      NSPredicate(format: "substanceName IN %@ AND time <= %@", substanceNames, Date.now as NSDate),
      Ingestion.confirmedPredicate,
    ])
    request.fetchLimit = 1
    return try context.fetch(request).first
  }

  private func activeIngestions(hoursBack: Int) throws -> JSONValue {
    let now = Date.now
    let request = PersistenceController.personalIngestionsRequest()
    let start = now.addingTimeInterval(-Double(hoursBack) * 3600)
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      request.predicate ?? NSPredicate(value: true),
      NSPredicate(format: "time <= %@ AND (time >= %@ OR endTime >= %@)", now as NSDate, start as NSDate, start as NSDate),
      Ingestion.confirmedPredicate,
    ])
    request.fetchLimit = limits.maxIngestions
    let ingestions = try context.fetch(request).reversed().map { ingestion -> JSONValue in
      var json = ingestionJSON(ingestion, includingExperience: true).object ?? [:]
      let duration = PersistenceController.shared.resolvedDuration(
        for: ingestion.substanceNameUnwrapped,
        route: ingestion.administrationRouteUnwrapped)
      let phases = [duration?.onset, duration?.comeup, duration?.peak, duration?.offset].compactMap { $0?.maxSec }
      let seconds = duration?.total?.maxSec ?? (phases.count == 4 ? phases.reduce(0, +) : nil)
      if let seconds, seconds.isFinite, seconds > 0 {
        // An infusion's effects last from its end
        let end = (ingestion.endTime ?? ingestion.timeUnwrapped).addingTimeInterval(seconds)
        json["expected_end"] = .string(AssistantFormat.date(end))
        json["status"] = .string(now < end ? "probably still active" : "probably worn off")
      } else {
        json["status"] = "unknown duration"
      }
      return .object(json)
    }
    return Self.success([
      "now": .string(AssistantFormat.date(now)),
      "hours_back": .number(Double(hoursBack)),
      "ingestions": .array(ingestions),
      "note": "Expected ends use the longest total duration listed; after-effects can last longer.",
    ])
  }

  // The index is downloaded whole and searched here, so the query never leaves the device
  private func searchAnodyneWiki(_ query: String) async throws -> JSONValue {
    guard !query.isEmpty else { return Self.error("'query' is required.") }
    let client = AnodyneClient.shared
    let request = await client.requestContext()
    let entries = try await client.indexEntries(using: request)
    guard await client.isCurrent(request) else { throw CancellationError() }
    let matches = entries
      .filter { entry in
        entry.matches(query) || entry.title.localizedCaseInsensitiveContains(query)
          || entry.abbreviations.contains { $0.localizedCaseInsensitiveContains(query) }
      }
      .prefix(limits.defaultListLength)
    return Self.success([
      "source": .string(request.baseURL.host ?? "AnodyneWiki"),
      "matches": .array(matches.map { entry in
        .object([
          "title": .string(entry.title),
          "abbreviations": AssistantFormat.strings(entry.abbreviations),
          "classes": AssistantFormat.strings(entry.classes),
        ])
      }),
    ])
  }

  // Only a title from AnodyneWiki's own index is requested, so names of the user's own substances stay private.
  // Userpages are fetched as a whole and filtered locally, so checking them also never leaks custom substance names.
  private func lookUpAnodyneWiki(_ query: String) async throws -> JSONValue {
    guard !query.isEmpty else { return Self.error("'substance' is required.") }
    let client = AnodyneClient.shared
    let request = await client.requestContext()
    let entries = try await client.indexEntries(using: request)
    guard await client.isCurrent(request) else { throw CancellationError() }
    let pwName = storedSubstanceName(for: query).flatMap { SubstanceRepo.shared.getSubstance(name: $0)?.name }
    let entry = entries.first(where: { $0.matches(query) }) ?? pwName
      .flatMap { name in entries.first { $0.matches(name) } }
    if let entry, case .found(let substance) = try await client.lookup(entry.title, using: request) {
      let noteNames = [substance.title, query] + substance.abbreviations + (pwName.map { [$0] } ?? [])
      let userNotes = await loadAnodyneUserNotes(matching: noteNames, using: request)
      guard await client.isCurrent(request) else { throw CancellationError() }
      var page = Self.trimmed((try? JSONValue(encoding: substance)) ?? .null, textLimit: limits.maxTextCharacters * 2)
        .object ?? [:]
      page["source"] = .string(request.baseURL.host ?? "AnodyneWiki")
      page["url"] = .string(AnodyneSubstance.pageURL(for: substance.title, at: request.baseURL).absoluteString)
      Self.attachUserNotes(userNotes, to: &page, limits: limits, instance: request.baseURL)
      return Self.success(page)
    }
    let noteNames = [query] + (pwName.map { [$0] } ?? [])
    let userNotes = await loadAnodyneUserNotes(matching: noteNames, using: request)
    guard await client.isCurrent(request) else { throw CancellationError() }
    guard !userNotes.isEmpty else {
      let missing = entry?.title ?? query
      return Self.error("AnodyneWiki has no page or user annotations for '\(missing)'. Try search_anodyne_wiki first.")
    }
    var page: [String: JSONValue] = [
      "source": .string(request.baseURL.host ?? "AnodyneWiki"),
      "note": "No main AnodyneWiki substance page was found; returning matching AnodyneWiki user annotations.",
    ]
    Self.attachUserNotes(userNotes, to: &page, limits: limits, instance: request.baseURL)
    return Self.success(page)
  }

  private func loadAnodyneUserNotes(
    matching names: [String], using request: AnodyneClient.RequestContext
  ) async -> [AnodyneUserNote] {
    if let fetched = try? await AnodyneClient.shared.userNotes(matching: names, using: request) {
      return fetched
    }
    return await AnodyneClient.shared.cachedUserNotes(matching: names, using: request)
  }

  private static func attachUserNotes(
    _ notes: [AnodyneUserNote],
    to page: inout [String: JSONValue],
    limits: Limits,
    instance: URL
  ) {
    guard !notes.isEmpty else { return }
    let shown = Array(notes.prefix(limits.defaultListLength))
    page["user_notes"] = .array(shown.map {
      anodyneUserNoteJSON($0, textLimit: limits.maxTextCharacters, instance: instance)
    })
    if notes.count > shown.count {
      page["user_notes_total"] = .number(Double(notes.count))
    }
  }

  static func anodyneUserNoteJSON(
    _ note: AnodyneUserNote, textLimit: Int, instance: URL = AnodyneSubstance.baseURL
  ) -> JSONValue {
    var json: [String: JSONValue] = [
      "user": .string(note.user),
      "substance": .string(note.substanceName),
      "url": .string(note.userPageURL(at: instance).absoluteString),
    ]
    if !note.routes.isEmpty {
      json["routes"] = .array(note.routes.map { route in
        var entry: [String: JSONValue] = ["route": .string(route.name)]
        if let dosage = route.dosage { entry["dosage"] = AssistantFormat.text(dosage, limit: textLimit) }
        if let onset = route.onset { entry["onset"] = AssistantFormat.text(onset, limit: textLimit) }
        if let comeup = route.comeup { entry["comeup"] = AssistantFormat.text(comeup, limit: textLimit) }
        if let duration = route.duration { entry["duration"] = AssistantFormat.text(duration, limit: textLimit) }
        return .object(entry)
      })
    }
    if !note.classes.isEmpty { json["classes"] = AssistantFormat.strings(note.classes) }
    if !note.forms.isEmpty { json["forms"] = AssistantFormat.strings(note.forms) }
    if !note.sources.isEmpty { json["sources"] = AssistantFormat.strings(note.sources) }
    if !note.indications.isEmpty { json["indications"] = AssistantFormat.strings(note.indications) }
    if !note.effects.isEmpty {
      json["effects"] = .array(note.effects.map { AssistantFormat.text($0, limit: textLimit) })
    }
    if !note.effectGroups.isEmpty {
      json["effect_groups"] = .array(note.effectGroups.map { group in
        .object([
          "heading": AssistantFormat.text(group.heading, limit: textLimit),
          "effects": .array(group.effects.map { AssistantFormat.text($0, limit: textLimit) }),
        ])
      })
    }
    if !note.afterEffects.isEmpty {
      json["after_effects"] = .array(note.afterEffects.map { AssistantFormat.text($0, limit: textLimit) })
    }
    if !note.tolerance.isEmpty {
      json["tolerance"] = .array(note.tolerance.map { AssistantFormat.text($0, limit: textLimit) })
    }
    if !note.odor.isEmpty { json["odor"] = AssistantFormat.strings(note.odor) }
    if !note.notes.isEmpty {
      json["notes"] = .array(note.notes.map { AssistantFormat.text($0, limit: textLimit) })
    }
    return .object(json)
  }

}
