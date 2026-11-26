import CoreData
import Foundation

// Tools that look things up in the journal
extension AssistantToolbox {
  func journalTools() -> [Tool] {
    let progress = "Looking through your journal…"
    return [
      Tool(
        name: "list_recent_experiences",
        description: "List the most recent experiences in the journal: reference, title, date, substances. Use it for an overview of recent sessions.",
        parameters: [
          Parameter(
            name: "limit",
            description: "How many experiences to list (default \(limits.defaultListLength), at most \(limits.maxListLength)).",
            kind: .integer),
        ],
        progress: progress,
        run: { [unowned self] arguments in
          let request = PersistenceController.experiencesRequest(prefetchingIngestions: true)
          request.fetchLimit = listLength(arguments)
          return try Self.success(["experiences": .array(context.fetch(request).map(experienceOverview))])
        }),
      Tool(
        name: "search_experiences",
        description: "Search the titles and notes of the user's experiences for a text. Use it when the user refers to a session by words likely in its title or notes.",
        parameters: [
          Parameter(
            name: "query",
            description: "Text to look for in titles and notes, ignoring case.",
            kind: .string,
            isRequired: true),
          Parameter(
            name: "limit",
            description: "How many matches to return (default \(limits.defaultListLength)).",
            kind: .integer),
        ],
        progress: progress,
        run: { [unowned self] arguments in
          let query = arguments.string("query")
          guard !query.isEmpty else { return Self.error("'query' is required.") }
          let experiences = try context.fetch(PersistenceController.experiencesRequest(
            containing: query,
            limit: listLength(arguments)))
          return Self.success(["matches": .array(experiences.map { experience in
            var overview = experienceOverview(experience).object ?? [:]
            overview["notes_excerpt"] = AssistantFormat.optionalText(experience.text, limit: 240)
            return .object(overview)
          })])
        }),
      Tool(
        name: "search_experiences_by_substance",
        description: "Find the experiences in which a substance was logged, newest first. Use it for questions like 'when did I last take MDMA?'.",
        parameters: [
          Parameter(name: "substance", description: "Substance name; parts of names match too.", kind: .string, isRequired: true),
          Parameter(
            name: "limit",
            description: "How many experiences to return (default \(limits.defaultListLength)).",
            kind: .integer),
        ],
        progress: progress,
        run: { [unowned self] arguments in
          let substance = arguments.string("substance")
          guard !substance.isEmpty else { return Self.error("'substance' is required.") }
          let request = PersistenceController.experiencesRequest(withSubstanceMatching: substance, limit: listLength(arguments))
          return try Self.success(["matches": .array(context.fetch(request).map(experienceOverview))])
        }),
      Tool(
        name: "get_experience_details",
        description: "Read one experience: its notes, every ingestion, timed notes and Shulgin ratings. Call it with a reference from another tool when you need more than an overview. The notes are cut at max_notes_chars; notes_truncated says whether there is more.",
        parameters: [
          Parameter(
            name: "experience_id",
            description: "The experience's reference, e.g. 'e3'.",
            kind: .string,
            isRequired: true),
          Parameter(
            name: "max_notes_chars",
            description: "How many characters of the notes to include (default \(limits.defaultNotesCharacters), at most \(limits.maxNotesCharacters)).",
            kind: .integer),
        ],
        progress: "Reading the session…",
        run: { [unowned self] arguments in
          guard let experience = experience(for: arguments.string("experience_id")) else {
            return Self
              .error("There is no experience '\(arguments.string("experience_id"))'. Use a reference another tool returned.")
          }
          let notesLimit = arguments.integer(
            "max_notes_chars",
            default: limits.defaultNotesCharacters,
            in: 0 ... limits.maxNotesCharacters)
          return experienceDetails(experience, notesLimit: notesLimit)
        }),
      Tool(
        name: "get_recent_ingestions",
        description: "List the ingestions of the last N days across all experiences, newest first, optionally of one substance.",
        parameters: [
          Parameter(name: "days_back", description: "How many days to look back (default 30, at most 730).", kind: .integer),
          Parameter(
            name: "substance",
            description: "Only ingestions of this substance; parts of names match too.",
            kind: .string),
        ],
        progress: progress,
        run: { [unowned self] arguments in
          let days = arguments.integer("days_back", default: 30, in: 1 ... 730)
          let request = PersistenceController.ingestionsRequest(
            since: Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60),
            substanceMatching: arguments.string("substance"),
            limit: limits.maxIngestions + 1)
          let ingestions = try context.fetch(request)
          return Self.success([
            "days_back": .number(Double(days)),
            "count": .number(Double(min(ingestions.count, limits.maxIngestions))),
            "more_not_listed": .bool(ingestions.count > limits.maxIngestions),
            "ingestions": .array(ingestions.prefix(limits.maxIngestions).map { ingestionJSON($0, includingExperience: true) }),
          ])
        }),
      Tool(
        name: "get_substance_usage_stats",
        description: "Count the user's own ingestions per substance over the last N days, most used first, with the first and last time and the days used. Use it for questions about patterns, like 'what have I used most this year?'.",
        parameters: [
          Parameter(name: "days_back", description: "How many days to look back (default 90, at most 1825).", kind: .integer),
        ],
        progress: progress,
        run: { [unowned self] arguments in
          let days = arguments.integer("days_back", default: 90, in: 1 ... 1825)
          // Every ingestion of the window is needed for counting; the cap only guards against runaway journals
          let request = PersistenceController.ingestionsRequest(
            since: Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60),
            personalOnly: true,
            limit: 20001)
          request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate ?? NSPredicate(value: true), Ingestion.confirmedPredicate,
          ])
          let fetched = try context.fetch(request)
          let ingestions = fetched.prefix(20000)
          let groups = Dictionary(grouping: ingestions, by: \.substanceNameUnwrapped)
            .sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
          let listed = groups.prefix(limits.maxListLength)
          return Self.success([
            "days_back": .number(Double(days)),
            "total_ingestions": .number(Double(ingestions.count)),
            "older_ingestions_omitted": .bool(fetched.count > ingestions.count),
            "substances": .array(listed.map { name, ingestions in
              let times = ingestions.map(\.timeUnwrapped)
              let days = Set(times.map { Calendar.current.startOfDay(for: $0) })
              return .object([
                "substance": .string(PersistenceController.shared.displayName(for: name)),
                "times_logged": .number(Double(ingestions.count)),
                "days_used": .number(Double(days.count)),
                "first_time": times.min().map { .string(AssistantFormat.date($0)) } ?? .null,
                "last_time": times.max().map { .string(AssistantFormat.date($0)) } ?? .null,
              ])
            }),
          ])
        }),
    ]
  }

  func experienceOverview(_ experience: Experience) -> JSONValue {
    let allEntries = experience.ingestionsSorted
    let confirmed = allEntries.filter { !$0.isUnconfirmed }
    let names = confirmed.map(\.substanceNameUnwrapped).uniqued()
    var overview: [String: JSONValue] = [
      "experience_id": .string(reference(for: experience)),
      "title": .string(experience.titleUnwrapped),
      "date": .string(AssistantFormat.date(experience.sortDateUnwrapped)),
      "is_favorite": .bool(experience.isFavorite),
      "ingestion_count": .number(Double(confirmed.count)),
      "substances": AssistantFormat.strings(names.map(PersistenceController.shared.displayName)),
    ]
    if allEntries.count > confirmed.count {
      overview["unconfirmed_ingestion_count"] = .number(Double(allEntries.count - confirmed.count))
    }
    return .object(overview)
  }

  func experienceDetails(_ experience: Experience, notesLimit: Int) -> JSONValue {
    let notes = experience.textUnwrapped
    var details = experienceOverview(experience).object ?? [:]
    details["notes"] = .string(String(notes.prefix(notesLimit)))
    details["notes_truncated"] = .bool(notes.count > notesLimit)
    details["notes_total_chars"] = .number(Double(notes.count))
    details["location"] = experience.location?.name.map { .string($0) } ?? .null
    details["ingestions"] = .array(experience.ingestionsSorted.prefix(limits.maxIngestions).map { ingestionJSON(
      $0,
      includingExperience: false) })
    details["timed_notes"] = .array(experience.timedNotesSorted.prefix(limits.maxIngestions).map { note in
      .object([
        "time": .string(AssistantFormat.date(note.timeUnwrapped)),
        "note": AssistantFormat.text(note.noteUnwrapped, limit: limits.maxTextCharacters),
      ])
    })
    details["ratings"] = .array(experience.ratingsUnwrapped.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
      .map { rating in
        .object([
          "time": rating.time.map { .string(AssistantFormat.date($0)) } ?? "overall",
          "rating": .string(rating.optionUnwrapped.stringRepresentation),
        ])
      })
    return AssistantToolbox.success(details)
  }

  func ingestionJSON(_ ingestion: Ingestion, includingExperience: Bool) -> JSONValue {
    var json: [String: JSONValue] = [
      "time": .string(AssistantFormat.date(ingestion.timeUnwrapped)),
      "substance": .string(PersistenceController.shared.displayName(for: ingestion.substanceNameUnwrapped)),
      "dose": AssistantFormat.number(ingestion.pureSubstanceDose),
      "units": .string(ingestion.pureUnits),
      "route": .string(ingestion.administrationRouteUnwrapped.rawValue),
    ]
    if ingestion.isEstimate {
      json["is_estimate"] = .bool(true)
      if let deviation = ingestion.pureSubstanceEstimatedDoseStandardDeviation {
        json["estimate_deviation"] = AssistantFormat.number(deviation)
      }
    }
    if ingestion.isUnconfirmed { json["is_unconfirmed"] = .bool(true) }
    if let customUnit = ingestion.customUnit, let dose = ingestion.doseUnwrapped {
      json["custom_unit_dose"] = .string("\(dose.formatted()) \(customUnit.unitUnwrapped) (\(customUnit.nameUnwrapped))")
    }
    if let formulation = ingestion.formulation {
      json["formulation"] = .string(formulation.nameUnwrapped)
    }
    if let endTime = ingestion.endTime {
      json["end_time"] = .string(AssistantFormat.date(endTime))
    }
    if !ingestion.isMine {
      json["consumer"] = .string(ingestion.consumerNameUnwrapped)
    }
    if !ingestion.noteUnwrapped.isEmpty {
      json["note"] = AssistantFormat.text(ingestion.noteUnwrapped, limit: min(500, limits.maxTextCharacters))
    }
    if includingExperience, let experience = ingestion.experience {
      json["experience_id"] = .string(reference(for: experience))
    }
    return .object(json)
  }

  private func listLength(_ arguments: [String: JSONValue]) -> Int {
    arguments.integer("limit", default: limits.defaultListLength, in: 1 ... limits.maxListLength)
  }

}
