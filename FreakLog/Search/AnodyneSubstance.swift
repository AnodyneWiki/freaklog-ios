import Foundation

// The parts of an AnodyneWiki (anodyne.wiki) substance the app shows. Built from the API's JSON, whose
// fields vary from substance to substance, and cached as this type, without the large experience report texts.
struct AnodyneSubstance: Codable, Hashable {
  struct Tier: Codable, Hashable {
    let lower: Double
    let upper: Double
    let unit: String
    let entries: Int
  }

  // Dose tiers of one route, statistically derived from logged doses. Light only has an upper and
  // extreme only a lower bound; common, strong and heavy are ranges.
  struct Dosing: Codable, Hashable {
    let method: String
    let light: Tier?
    let common: Tier?
    let strong: Tier?
    let heavy: Tier?
    let extreme: Tier?

    var route: AdministrationRoute? {
      AnodyneSubstance.route(forMethod: method)
    }

    var unit: String? {
      [light, common, strong, heavy, extreme].lazy.compactMap { $0?.unit }.first { !$0.isEmpty }
    }

    var totalEntries: Int {
      [light, common, strong, heavy, extreme].compactMap { $0?.entries }.reduce(0, +)
    }

    // In PsychonautWiki's form, so it is shown like its ranges: AnodyneWiki's light tier ends where common
    // starts and has no lower bound, so there is no threshold
    var roaDose: RoaDose? {
      guard let unit, common != nil || strong != nil || heavy != nil else { return nil }
      return RoaDose(units: unit, lightMin: nil, commonMin: common?.lower, strongMin: strong?.lower, heavyMin: heavy?.lower)
    }

    // As editor values: where common, strong and heavy start. Light has no lower bound on AnodyneWiki.
    func doseValues(for route: AdministrationRoute) -> CustomRoaCodable {
      var values = CustomRoaCodable(administrationRoute: route, doseUnits: unit)
      values.commonDose = common?.lower
      values.strongDose = strong?.lower
      values.heavyDose = heavy?.lower
      return values
    }
  }

  struct EffectGroup: Codable, Hashable {
    let name: String
    let effects: [String]
  }

  struct Schedule: Codable, Hashable {
    let country: String
    let schedule: String
  }

  struct Reagent: Codable, Hashable {
    let name: String
    let colors: [String]
  }

  struct Link: Codable, Hashable {
    let title: String
    let url: URL
  }

  let title: String
  var abbreviations: [String] = []
  var aliases: [String] = []
  var slang: [String] = []
  var classes: [String] = []
  var dosing: [Dosing] = []
  var durationOfAction: String?
  var halfLife: String?
  var interactions: String?
  var mechanismOfAction: String?
  var metabolism: String?
  var healthEffects: String?
  var drugWarnings: String?
  var reportedFatalDose: String?
  var treatment: String?
  var effectGroups: [EffectGroup] = []
  var scheduling: [Schedule] = []
  var reagents: [Reagent] = []
  var erowidReports: [Link] = []
  var redditReports: [Link] = []
  var references: [Link] = []
  // A 2D structure drawing as SVG, and the molecular formula and mass
  var structureSVG: String?
  var formula: String?
  var molarMass: String?

  static let defaultBaseURL = URL(string: "https://anodyne.wiki")!

  // The AnodyneWiki instance to load from and link to, set in Settings > AnodyneWiki
  static var baseURL: URL {
    UserDefaults.standard.string(forKey: PersistenceController.anodyneInstanceURLKey)
      .flatMap(instanceURL(from:)) ?? defaultBaseURL
  }

  // An instance's address as entered, e.g. "wiki.example.org" or "https://wiki.example.org/", or nil when it
  // isn't a web address
  static func instanceURL(from text: String) -> URL? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if !text.contains("://") {
      text = "https://" + text
    }
    while text.hasSuffix("/") {
      text.removeLast()
    }
    guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()),
          let host = url.host(), !host.isEmpty, url.query == nil
    else { return nil }
    return url
  }

  var pageURL: URL {
    Self.pageURL(for: title)
  }

  static func pageURL(for title: String, at instance: URL = baseURL) -> URL {
    let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    return URL(string: "\(instance.absoluteString)/substance/\(encoded)") ?? instance
  }

  // The short name people use, e.g. MDMA for 3,4-Methylenedioxymethamphetamine
  var commonName: String {
    if title.count > 24, let abbreviation = abbreviations.first(where: { $0.count <= 24 }) {
      return abbreviation
    }
    return title
  }

  var hasPharmacologyTexts: Bool {
    [interactions, mechanismOfAction, metabolism, healthEffects, drugWarnings, reportedFatalDose, treatment]
      .contains { $0 != nil }
  }

  static func route(forMethod method: String) -> AdministrationRoute? {
    let method = method.lowercased()
    let routes: [(String, AdministrationRoute)] = [
      ("sublingual", .sublingual), ("buccal", .buccal), ("oral", .oral), ("insufflat", .insufflated),
      ("intranasal", .insufflated), ("rectal", .rectal), ("transdermal", .transdermal),
      ("subcutaneous", .subcutaneous), ("intramuscular", .intramuscular), ("intravenous", .intravenous),
      ("smok", .smoked), ("vapori", .inhaled), ("inhal", .inhaled),
    ]
    return routes.first { method.contains($0.0) }?.1
  }
}

// MARK: - Reading the API's JSON

extension AnodyneSubstance {
  // The API answers unknown names with {"NotFound": true}
  init?(apiJSON json: [String: Any]) {
    guard json["NotFound"] as? Bool != true, let title = json["Title"] as? String else { return nil }
    self.title = title.anodyneCleaned
    abbreviations = Self.strings(json["Abbreviation"])
    // Chemical index names such as "Benzeneethanamine, 4-fluoro-2,5-dimethoxy-" aren't names people use
    aliases = Self.strings(json["Aliases"]).filter { !$0.contains(", ") }
    slang = Self.strings(json["Slang"]).map { $0.trimmingCharacters(in: .whitespaces) }
    classes = Self.strings(json["Classes"])
    dosing = (json["Dosing Info"] as? [[String: Any]] ?? []).compactMap(Self.dosing)
    durationOfAction = Self.text(json["DurationOfAction"])
    halfLife = Self.text(json["Biological Half-Life"])
    interactions = Self.text(json["Interactions"])
    mechanismOfAction = Self.text(json["Mechanism of Action"])
    metabolism = Self.text(json["Metabolism/Metabolites"])
    healthEffects = Self.text(json["Health Effects"])
    drugWarnings = Self.text(json["Drug Warnings"])
    reportedFatalDose = Self.text(json["Reported Fatal Dose"])
    treatment = Self.text(json["Treatment"])
    effectGroups = (json["Subjective Effects"] as? [String: Any] ?? [:])
      .map { EffectGroup(name: $0.key, effects: Self.strings($0.value)) }
      .filter { !$0.effects.isEmpty }
      .sorted { $0.name < $1.name }
    scheduling = (json["Scheduling"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let country = entry["gov"] as? String, let schedule = entry["schedule"] as? String else { return nil }
      // Some carry wiki link markup, "target|label", of which only the label is shown
      let label = (schedule.anodyneCleaned.components(separatedBy: "|").last ?? schedule)
        .replacingOccurrences(of: ". substance", with: ".")
      return Schedule(country: country, schedule: label.trimmingCharacters(in: .whitespaces))
    }
    reagents = (json["Reagents"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let name = entry["Name"] as? String else { return nil }
      return Reagent(name: name, colors: Self.strings(entry["Colors"]))
    }
    erowidReports = (json["Erowid Experience Reports"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let id = entry["Id"] as? Int, let title = entry["Title"] as? String,
            let url = URL(string: "https://www.erowid.org/experiences/exp.php?ID=\(id)")
      else { return nil }
      return Link(title: title.anodyneCleaned, url: url)
    }
    redditReports = (json["Reddit Experience Reports"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let title = entry["title"] as? String, let urlString = entry["url"] as? String,
            let url = URL(string: urlString)
      else { return nil }
      return Link(title: title.anodyneCleaned, url: url)
    }
    structureSVG = Self.structureSVG(json)
    formula = (json["MolecularFormula"] as? String).map(Self.subscripted).flatMap { Self.text($0) }
    molarMass = Self.text(json["MolecularWeight"])
    references = (json["References"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let name = entry["Name"] as? String,
            let link = (entry["Urls"] as? [[String: Any]])?.first?["Link"] as? String,
            let url = URL(string: link)
      else { return nil }
      return Link(title: name, url: url)
    }
  }

  private static func dosing(_ json: [String: Any]) -> Dosing? {
    guard let method = json["Method"] as? String, let tiers = json["Tiers"] as? [String: Any] else { return nil }
    func tier(_ name: String) -> Tier? {
      guard let tier = tiers[name] as? [String: Any],
            let lower = (tier["Lower"] as? NSNumber)?.doubleValue,
            let upper = (tier["Upper"] as? NSNumber)?.doubleValue
      else { return nil }
      return Tier(
        lower: lower,
        upper: upper,
        unit: tier["Unit"] as? String ?? "",
        entries: (tier["Entries"] as? NSNumber)?.intValue ?? 0
      )
    }
    let dosing = Dosing(
      method: method,
      light: tier("Light"),
      common: tier("Common"),
      strong: tier("Strong"),
      heavy: tier("Heavy"),
      extreme: tier("Extreme")
    )
    return dosing.totalEntries > 0 ? dosing : nil
  }

  // Most substances have the SVG as text, some (e.g. progesterone) base64 encoded
  private static func structureSVG(_ json: [String: Any]) -> String? {
    let svg = json["Structure"] as? String
      ?? (json["StructureBase64"] as? String)
        .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        .flatMap { String(data: $0, encoding: .utf8) }
    return svg?.contains("<svg") == true ? svg : nil
  }

  // "C<sub>11</sub>H<sub>15</sub>NO<sub>2</sub>" reads as "C₁₁H₁₅NO₂"
  private static func subscripted(_ formula: String) -> String {
    let subscripts: [Character: Character] = [
      "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]
    var result = ""
    var isInSubscript = false
    var rest = Substring(formula)
    while !rest.isEmpty {
      if rest.hasPrefix("<sub>") {
        isInSubscript = true
        rest = rest.dropFirst(5)
      } else if rest.hasPrefix("</sub>") {
        isInSubscript = false
        rest = rest.dropFirst(6)
      } else {
        let character = rest.removeFirst()
        result.append(isInSubscript ? subscripts[character] ?? character : character)
      }
    }
    return result
  }

  // A string, or a list of strings
  private static func strings(_ value: Any?) -> [String] {
    if let string = value as? String {
      return string.isEmpty ? [] : [string.anodyneCleaned]
    }
    return (value as? [Any] ?? []).compactMap { ($0 as? String)?.anodyneCleaned }.filter { !$0.isEmpty }
  }

  private static func text(_ value: Any?) -> String? {
    guard let string = (value as? String)?.anodyneCleaned, !string.isEmpty else { return nil }
    return string
  }
}

// MARK: - Index

// One entry of AnodyneWiki's substance index, used to search it and to find a substance by a short name
struct AnodyneIndexEntry: Codable, Hashable, Identifiable {
  let title: String
  let abbreviations: [String]
  let classes: [String]

  var id: String { title }

  init?(apiJSON json: [String: Any]) {
    guard let title = json["Title"] as? String, json["NoBuild"] as? Bool != true else { return nil }
    self.title = title
    if let abbreviation = json["Abr"] as? String {
      abbreviations = [abbreviation]
    } else {
      abbreviations = json["Abr"] as? [String] ?? []
    }
    classes = json["Classes"] as? [String] ?? []
  }

  func matches(_ name: String) -> Bool {
    ([title] + abbreviations).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
  }
}

extension AnodyneIndexEntry {
  static func classKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func classOptions(in entries: [Self]) -> [String] {
    var names: [String: String] = [:]
    for entry in entries {
      for name in entry.classes {
        let key = classKey(name)
        if !key.isEmpty, names[key] == nil {
          names[key] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
    }
    return names.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  static func search(_ entries: [Self], text: String, classKeys: Set<String>) -> [Self] {
    let matchingClass = classKeys.isEmpty ? entries : entries.filter { entry in
      entry.classes.contains { classKeys.contains(classKey($0)) }
    }
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return matchingClass }

    var prefixes: [Self] = []
    var otherMatches: [Self] = []
    for entry in matchingClass {
      let names = [entry.title] + entry.abbreviations
      if names.contains(where: { $0.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive], locale: .current) != nil }) {
        prefixes.append(entry)
      } else if (names + entry.classes).contains(where: { $0.localizedStandardContains(text) }) {
        otherMatches.append(entry)
      }
    }
    return prefixes + otherMatches
  }
}

extension String {
  // AnodyneWiki texts carry some HTML, tags such as <sub> and entities such as &nbsp;, and some
  // Wikipedia footnote templates such as {-{Efn|...|group=note}-}
  var anodyneCleaned: String {
    var text = replacingOccurrences(of: "\\{-?\\{[\\s\\S]*?\\}-?\\}", with: "", options: .regularExpression)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
    for (entity, character) in entities {
      text = text.replacingOccurrences(of: entity, with: character)
    }
    return text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - User notes

// What one AnodyneWiki user wrote about a substance they tried, from their userpage
struct AnodyneUserNote: Codable, Hashable, Identifiable {
  struct Route: Codable, Hashable {
    let name: String
    let dosage: String?
    let onset: String?
    let comeup: String?
    let duration: String?
  }

  // Effects the user noted for one route, dose or condition
  struct EffectGroup: Codable, Hashable {
    let heading: String
    let effects: [String]
  }

  let user: String
  let substanceName: String
  var routes: [Route] = []
  var classes: [String] = []
  var forms: [String] = []
  var sources: [String] = []
  var indications: [String] = []
  var effects: [String] = []
  var effectGroups: [EffectGroup] = []
  var afterEffects: [String] = []
  var tolerance: [String] = []
  var odor: [String] = []
  var notes: [String] = []

  var id: String { "\(user)/\(substanceName)" }

  var userPageURL: URL { userPageURL(at: AnodyneSubstance.baseURL) }

  func userPageURL(at instance: URL) -> URL {
    let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
    return URL(string: "\(instance.absoluteString)/user/\(encoded)") ?? instance
  }

  // E.g. "Oral 40–91 mg, Insufflated 22 mg"
  var routesSummary: String {
    routes.map { route in [route.name, route.dosage].compactMap { $0 }.joined(separator: " ") }
      .joined(separator: ", ")
  }

  var hasDetails: Bool {
    ![routes.isEmpty, classes.isEmpty, forms.isEmpty, sources.isEmpty, indications.isEmpty, effects.isEmpty,
      effectGroups.isEmpty, afterEffects.isEmpty, tolerance.isEmpty, odor.isEmpty, notes.isEmpty].allSatisfy { $0 }
  }

  // The substances a userpage lists under TriedSubstances
  static func notes(fromUserJSON json: [String: Any]) -> [AnodyneUserNote] {
    guard let user = json["Title"] as? String else { return [] }
    return (json["TriedSubstances"] as? [[String: Any]] ?? []).compactMap { entry in
      guard let name = entry["Name"] as? String else { return nil }
      func texts(_ keys: String...) -> [String] {
        keys.flatMap { key -> [String] in
          if let string = entry[key] as? String {
            return [string]
          }
          return (entry[key] as? [Any] ?? []).compactMap { $0 as? String }
        }
        .map(\.anodyneUserMarkupCleaned)
        .filter { !$0.isEmpty }
      }
      let note = AnodyneUserNote(
        user: user,
        substanceName: name,
        routes: (entry["Routes"] as? [[String: Any]] ?? []).compactMap(Self.route),
        classes: texts("Classes"),
        forms: texts("Forms", "Salts"),
        sources: texts("Sources", "Source"),
        indications: texts("Indication"),
        effects: texts("Effects", "Adverse"),
        effectGroups: (entry["DEffects"] as? [[String: Any]] ?? []).compactMap(Self.effectGroup),
        afterEffects: texts("After"),
        tolerance: texts("Tolerance"),
        odor: texts("Odor"),
        notes: texts("Notes", "Note")
      )
      return note
    }
  }

  private static func route(_ json: [String: Any]) -> Route? {
    guard let name = json["Name"] as? String, !name.isEmpty else { return nil }
    func text(_ key: String) -> String? {
      guard let value = json[key] as? String, !value.isEmpty else { return nil }
      return value.anodyneUserMarkupCleaned
    }
    return Route(
      name: name.capitalized,
      dosage: text("Dosage").map(Self.spacedDosage),
      onset: text("Onset"),
      comeup: text("Comeup"),
      duration: text("Duration") ?? text("Active")
    )
  }

  private static func effectGroup(_ json: [String: Any]) -> EffectGroup? {
    let effects = (json["Effects"] as? [Any] ?? []).compactMap { ($0 as? String)?.anodyneUserMarkupCleaned }
    guard !effects.isEmpty else { return nil }
    let parts = ["Route", "Dosage"].compactMap { json[$0] as? String }.filter { !$0.isEmpty }
    let condition = (json["Condition"] as? String)?.anodyneUserMarkupCleaned
    let heading = parts.isEmpty ? condition ?? "Effects" : parts.joined(separator: " ") + (condition.map { " (\($0))" } ?? "")
    return EffectGroup(heading: heading, effects: effects)
  }

  // "40-91mg" reads as "40–91 mg"
  private static func spacedDosage(_ dosage: String) -> String {
    dosage
      .replacingOccurrences(of: "(\\d)-(\\d)", with: "$1–$2", options: .regularExpression)
      .replacingOccurrences(of: "(\\d)([a-zµμ]+)$", with: "$1 $2", options: .regularExpression)
  }
}

extension String {
  // Userpages use AnodyneWiki's own markup, rendered by its frontend (anodyne-frontend, template "user"):
  // {sev 'light'} and links such as {xeff 'teeth-grinding'} or {sub 'target' 'label'} show their text,
  // {p}...{Ep} and similar are HTML tags, {gt}, {lt} and {apos} are characters and *text* is emphasis.
  var anodyneUserMarkupCleaned: String {
    var text = self
    for tag in ["b", "p", "ul", "s", "i", "sub"] {
      text = text.replacingOccurrences(of: "{\(tag)}", with: "").replacingOccurrences(of: "{E\(tag)}", with: " ")
    }
    text = text.replacingOccurrences(of: "{br}", with: " ")
      .replacingOccurrences(of: "{apos}", with: "'")
      .replacingOccurrences(of: "{rev}", with: "reverse")
      .replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
    // Two-value links show their label, one-value ones their value; effect names are written with hyphens
    text = text.replacingOccurrences(of: "\\{\\w+\\s+'[^']*'\\s+'([^']*)'\\}", with: "$1", options: .regularExpression)
    guard let regex = try? NSRegularExpression(pattern: "\\{(\\w+)\\s+'([^']*)'\\}") else { return text.anodyneCleaned }
    // < and > come back after HTML tags are stripped, so they can't be taken for tags
    var result = ""
    var rest = text.startIndex
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      guard let whole = Range(match.range, in: text),
            let tag = Range(match.range(at: 1), in: text),
            let value = Range(match.range(at: 2), in: text)
      else { continue }
      result += text[rest ..< whole.lowerBound]
      result += text[tag] == "xeff" ? text[value].replacingOccurrences(of: "-", with: " ") : String(text[value])
      rest = whole.upperBound
    }
    result += text[rest...]
    return result.anodyneCleaned
      .replacingOccurrences(of: "{gt}", with: ">")
      .replacingOccurrences(of: "{lt}", with: "<")
  }
}
