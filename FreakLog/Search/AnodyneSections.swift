import SwiftUI
import WrappingHStack

// Loads a substance's AnodyneWiki data: right away when it is cached or automatic loading is on,
// otherwise only once the user asks for it.
@MainActor
final class AnodyneLoadModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case loading
    case found(AnodyneSubstance)
    case notFound
    case failed
  }

  @Published private var loadedPhase = Phase.idle
  // What AnodyneWiki's users wrote about the substance on their userpages
  @Published private(set) var userNotes: [AnodyneUserNote] = []
  let name: String
  let otherNames: [String]
  private var context: AnodyneClient.RequestContext?

  var phase: Phase {
    context?.baseURL == AnodyneSubstance.baseURL ? loadedPhase : .idle
  }

  init(name: String, otherNames: [String] = []) {
    self.name = name
    self.otherNames = otherNames
  }

  var substance: AnodyneSubstance? {
    if case let .found(substance) = phase { substance } else { nil }
  }

  func start(loadingIfNotCached: Bool = AnodyneClient.isAutomaticLoadingEnabled) async {
    guard let context = await prepareContext() else { return }
    if case .found = phase {
      await loadUserNotes(online: loadingIfNotCached, using: context)
      return
    }
    guard phase == .idle else { return }
    let cached = await AnodyneClient.shared.cachedLookup(for: name, using: context)
    guard await canPresent(context), phase == .idle else { return }
    if let cached, cached != .notFound || otherNames.isEmpty {
      loadedPhase = Self.makePhase(for: cached)
      await loadUserNotes(online: loadingIfNotCached, using: context)
    } else if loadingIfNotCached {
      await load(using: context)
    }
  }

  func load() async {
    guard let context = await prepareContext(), phase != .loading else { return }
    await load(using: context)
  }

  private func load(using context: AnodyneClient.RequestContext) async {
    loadedPhase = .loading
    do {
      let lookup = try await AnodyneClient.shared.lookup(name, otherNames: otherNames, using: context)
      guard await canPresent(context) else { return }
      loadedPhase = Self.makePhase(for: lookup)
    } catch {
      guard await canPresent(context) else { return }
      loadedPhase = .failed
    }
    await loadUserNotes(online: true, using: context)
  }

  private func prepareContext() async -> AnodyneClient.RequestContext? {
    let current = await AnodyneClient.shared.requestContext()
    guard !Task.isCancelled, current.baseURL == AnodyneSubstance.baseURL else { return nil }
    if context != current {
      context = current
      loadedPhase = .idle
      userNotes = []
    }
    return current
  }

  private func canPresent(_ request: AnodyneClient.RequestContext) async -> Bool {
    let current = await AnodyneClient.shared.isCurrent(request)
    guard context == request else { return false }
    guard current, request.baseURL == AnodyneSubstance.baseURL, !Task.isCancelled else {
      loadedPhase = .idle
      userNotes = []
      return false
    }
    return true
  }

  // Userpages name substances by their AnodyneWiki title, sometimes by an abbreviation. Offline, the
  // notes saved last are shown, however old.
  private func loadUserNotes(online: Bool, using context: AnodyneClient.RequestContext) async {
    guard Self.showsUserNotes else {
      userNotes = []
      return
    }
    guard let substance else { return }
    let names = [substance.title, name] + substance.abbreviations
    let notes: [AnodyneUserNote]
    if online, let refreshed = try? await AnodyneClient.shared.userNotes(matching: names, using: context) {
      notes = refreshed
    } else {
      notes = await AnodyneClient.shared.cachedUserNotes(matching: names, using: context)
    }
    guard await canPresent(context) else { return }
    userNotes = Self.showsUserNotes ? notes : []
  }

  private static var showsUserNotes: Bool {
    UserDefaults.standard.object(forKey: PersistenceController.showsAnodyneUserNotesKey) as? Bool ?? true
  }

  private static func makePhase(for lookup: AnodyneClient.Lookup) -> Phase {
    switch lookup {
    case let .found(substance): .found(substance)
    case .notFound: .notFound
    }
  }
}

struct AnodyneSourcesMenu: View {
  @ObservedObject var model: AnodyneLoadModel
  var psychonautWikiURL: URL?

  var body: some View {
    Menu {
      if let psychonautWikiURL {
        Button {
          Navigator.shared.openInCurrentTab(.webView(articleURL: psychonautWikiURL))
        } label: {
          Label("PsychonautWiki Article", systemImage: "doc.text")
        }
      }
      switch model.phase {
      case .idle, .failed:
        Button {
          Task { await model.load() }
        } label: {
          Label(model.phase == .failed ? "Retry AnodyneWiki" : "Load AnodyneWiki", systemImage: "arrow.down.circle")
        }
      case .loading:
        Text("Loading AnodyneWiki…")
      case .notFound:
        Text("No AnodyneWiki Page")
      case let .found(substance):
        Button {
          Navigator.shared.openInCurrentTab(.webView(articleURL: substance.pageURL))
        } label: {
          Label("AnodyneWiki Page", systemImage: "books.vertical")
        }
      }
    } label: {
      Label("Sources", systemImage: "books.vertical")
    }
  }
}

struct AnodyneLoadStatus: View {
  @ObservedObject var model: AnodyneLoadModel

  var body: some View {
    switch model.phase {
    case .loading:
      Section {
        HStack(spacing: 12) {
          ProgressView()
          Text("Loading from AnodyneWiki…")
            .foregroundStyle(.secondary)
        }
      }
    case .failed:
      Section {
        Text("AnodyneWiki couldn't be loaded.")
          .foregroundStyle(.secondary)
      }
    case .idle, .found, .notFound:
      EmptyView()
    }
  }
}

// MARK: - Topics combining both sources

// PsychonautWiki's effects summary and AnodyneWiki's reported effects
struct EffectsSection: View {
  let summary: String?
  let anodyne: AnodyneSubstance?

  var body: some View {
    let groups = anodyne?.effectGroups ?? []
    if summary != nil || !groups.isEmpty {
      Section("Effects") {
        if let summary {
          Text(summary)
        }
        ForEach(groups, id: \.name) { group in
          VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
              .font(.subheadline)
              .foregroundStyle(.secondary)
            ChipList(items: group.effects)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }
}

// PsychonautWiki's interaction list and AnodyneWiki's interaction literature
struct InteractionsSection: View {
  let substance: Substance?
  let anodyne: AnodyneSubstance?

  var body: some View {
    let interactions = substance?.interactions
    if interactions != nil || anodyne?.interactions != nil {
      Section("Interactions") {
        if let substance, let interactions {
          InteractionsGroup(interactions: interactions, substance: substance)
        }
        if let literature = anodyne?.interactions {
          ExpandableText(title: "From the Literature", text: literature)
        }
      }
    }
  }
}

// AnodyneWiki's timings for substances without a PsychonautWiki timeline: a timeline for each route its users
// noted timings for, and the duration of action and half-life
struct AnodyneDurationSection: View {
  let anodyne: AnodyneSubstance
  var isShowingRouteTimings = true

  static let timingFootnote =
    "The duration is AnodyneWiki's: what its users noted for this route, or the substance's duration of action."

  var body: some View {
    let routes = isShowingRouteTimings ? AnodyneFallbackStore.shared.routesWithTimings(for: anodyne.title) : []
    if !routes.isEmpty || anodyne.durationOfAction != nil || anodyne.halfLife != nil {
      Section {
        ForEach(routes, id: \.self) { route in
          VStack(alignment: .leading, spacing: 8) {
            Text(route.rawValue.localizedCapitalized)
              .font(.headline)
            RoaPreview(
              substanceName: anodyne.title,
              route: route,
              roaDose: nil,
              roaDuration: AnodyneFallbackStore.shared.duration(for: anodyne.title, route: route)
            )
          }
        }
        AnodyneDurationRows(anodyne: anodyne)
      } header: {
        Text("Duration")
      } footer: {
        if !routes.isEmpty {
          Text("Route timings are what AnodyneWiki's users noted.")
        }
      }
    }
  }
}

struct AnodyneDurationRows: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if let duration = anodyne.durationOfAction {
      DetailRow(title: "Duration of Action", text: duration)
    }
    if let halfLife = anodyne.halfLife {
      DetailRow(title: "Biological Half-Life", text: halfLife)
    }
  }
}

// Everything AnodyneWiki's users wrote about the substance, each opening their whole note
struct AnodyneUserNotesScreen: View {
  let notes: [AnodyneUserNote]

  var body: some View {
    List {
      Section {
        ForEach(notes) { note in
          NavigationLink(value: GlobalNavigationDestination.anodyneUserNote(note: note)) {
            VStack(alignment: .leading, spacing: 3) {
              Text(note.user)
                .font(.headline)
              if !note.routesSummary.isEmpty {
                Text(note.routesSummary)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              if let text = note.notes.first ?? note.effects.first {
                Text(text)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            .padding(.vertical, 2)
          }
        }
      } footer: {
        Text("Personal experiences AnodyneWiki users shared on their userpages. They are not advice.")
      }
    }
    .navigationTitle("User Notes")
  }
}

// The substance's 2D structure, molecular formula and molar mass
struct AnodyneChemistryRows: View {
  let anodyne: AnodyneSubstance
  let substanceName: String

  var body: some View {
    if let svg = anodyne.structureSVG, let structure = MoleculeStructureView(svg: svg, substanceName: substanceName) {
      structure
    }
    if let formula = anodyne.formula {
      LabeledContent("Formula", value: formula)
    }
    if let molarMass = anodyne.molarMass {
      LabeledContent("Molar Mass", value: molarMass)
    }
  }
}

// Experience reports or references, each opening its page
struct AnodyneLinksScreen: View {
  let title: String
  let links: [AnodyneSubstance.Link]

  var body: some View {
    List(links, id: \.url) { link in
      NavigationLink(link.title, value: GlobalNavigationDestination.webView(articleURL: link.url))
    }
    .navigationTitle(title)
  }
}

// One user's whole note about a substance, laid out like their userpage
struct AnodyneUserNoteScreen: View {
  let note: AnodyneUserNote

  var body: some View {
    List {
      if !note.routes.isEmpty {
        Section("Routes") {
          ForEach(note.routes, id: \.self) { route in
            VStack(alignment: .leading, spacing: 3) {
              LabeledContent(route.name, value: route.dosage ?? "")
              let times = [("Onset", route.onset), ("Come-up", route.comeup), ("Duration", route.duration)]
                .compactMap { label, value in value.map { "\(label) \($0)" } }
              if !times.isEmpty {
                Text(times.joined(separator: " · "))
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      if !note.classes.isEmpty || !note.forms.isEmpty {
        Section("Classes & Forms") {
          if !note.classes.isEmpty {
            ChipList(items: note.classes)
          }
          ForEach(note.forms, id: \.self) { form in
            Text(form)
          }
        }
      }
      textsSection("Sources", note.sources)
      textsSection("Indications", note.indications)
      textsSection("Effects", note.effects)
      ForEach(note.effectGroups, id: \.self) { group in
        textsSection("Effects: \(group.heading)", group.effects)
      }
      textsSection("After Effects", note.afterEffects)
      textsSection("Tolerance", note.tolerance)
      textsSection("Odor", note.odor)
      textsSection("Notes", note.notes)
      Section {
        NavigationLink(value: GlobalNavigationDestination.webView(articleURL: note.userPageURL)) {
          Label("\(note.user)'s Userpage", systemImage: "person.crop.circle")
        }
      } footer: {
        Text("About \(note.substanceName), from AnodyneWiki. A personal experience, not advice.")
      }
    }
    .navigationTitle(note.user)
  }

  @ViewBuilder
  private func textsSection(_ title: String, _ texts: [String]) -> some View {
    if !texts.isEmpty {
      Section(title) {
        ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
          Text(text)
            .textSelection(.enabled)
        }
      }
    }
  }
}

// MARK: - AnodyneWiki topics

// Every AnodyneWiki topic that has no PsychonautWiki counterpart on the screen showing it
struct AnodyneTopicSections: View {
  let anodyne: AnodyneSubstance
  var userNotes: [AnodyneUserNote] = []
  // The PsychonautWiki screen shows these topics combined with its own
  var isIncludingSharedTopics = true
  // The custom substance screen shows them with the user's own routes
  var isShowingRouteTimings = true

  var body: some View {
    if isIncludingSharedTopics {
      EffectsSection(summary: nil, anodyne: anodyne)
    }
    AnodyneReportsSection(anodyne: anodyne, userNotes: userNotes)
    AnodyneLoggedDosesSection(anodyne: anodyne)
    if isIncludingSharedTopics {
      AnodyneDurationSection(anodyne: anodyne, isShowingRouteTimings: isShowingRouteTimings)
      InteractionsSection(substance: nil, anodyne: anodyne)
      ToxicitySection(substance: nil, anodyne: anodyne)
    }
    AnodyneWarningsSection(anodyne: anodyne)
    AnodyneReagentsSection(anodyne: anodyne)
    AnodyneLegalStatusSection(anodyne: anodyne)
    AnodynePharmacologySection(anodyne: anodyne)
  }
}

struct AnodyneLoggedDosesSection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if !anodyne.dosing.isEmpty {
      Section {
        ForEach(anodyne.dosing, id: \.method) { dosing in
          AnodyneDosingRow(dosing: dosing)
        }
      } header: {
        Text("Dose")
      } footer: {
        Text(AnodyneDosingRow.disclaimer)
      }
    }
  }
}

struct AnodyneWarningsSection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if anodyne.healthEffects != nil || anodyne.drugWarnings != nil {
      Section("Health Warnings") {
        if let healthEffects = anodyne.healthEffects {
          ExpandableText(title: "Health Effects", text: healthEffects)
        }
        if let drugWarnings = anodyne.drugWarnings {
          ExpandableText(title: "Drug Warnings", text: drugWarnings)
        }
      }
    }
  }
}

struct AnodyneReagentsSection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if !anodyne.reagents.isEmpty {
      Section {
        ForEach(anodyne.reagents, id: \.name) { reagent in
          HStack {
            Text(reagent.name)
            Spacer()
            HStack(spacing: 3) {
              ForEach(Array(reagent.colors.enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color(anodyneHex: hex))
                  .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
                  .frame(width: 16, height: 16)
              }
            }
            .accessibilityHidden(true)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(reagent.name) reaction")
          .accessibilityValue(reagent.colors.joined(separator: ", "))
        }
      } header: {
        Text("Reagent Tests")
      } footer: {
        Text("Expected colors, changing over time from left to right.")
      }
    }
  }
}

struct AnodyneLegalStatusSection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if !anodyne.scheduling.isEmpty {
      Section("Legal Status") {
        ForEach(anodyne.scheduling, id: \.self) { schedule in
          LabeledContent(schedule.country, value: schedule.schedule)
        }
      }
    }
  }
}

struct AnodynePharmacologySection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if anodyne.mechanismOfAction != nil || anodyne.metabolism != nil {
      Section("Pharmacology") {
        if let mechanism = anodyne.mechanismOfAction {
          ExpandableText(title: "Mechanism of Action", text: mechanism)
        }
        if let metabolism = anodyne.metabolism {
          ExpandableText(title: "Metabolism", text: metabolism)
        }
      }
    }
  }
}

struct AnodyneReportsSection: View {
  let anodyne: AnodyneSubstance
  var userNotes: [AnodyneUserNote] = []
  @AppStorage(PersistenceController.showsAnodyneUserNotesKey) private var showsUserNotes = true

  // One row per source, so the page stays short however many reports there are
  var body: some View {
    let hasUserNotes = showsUserNotes && !userNotes.isEmpty
    if hasUserNotes || !anodyne.erowidReports.isEmpty || !anodyne.redditReports.isEmpty {
      Section("Experience Reports") {
        if hasUserNotes {
          NavigationLink(value: GlobalNavigationDestination.anodyneUserNotes(notes: userNotes)) {
            LabeledContent("AnodyneWiki User Notes", value: userNotes.count.formatted())
          }
        }
        reportsLink("Erowid", reports: anodyne.erowidReports)
        reportsLink("Reddit", reports: anodyne.redditReports)
      }
    }
  }

  @ViewBuilder
  private func reportsLink(_ source: String, reports: [AnodyneSubstance.Link]) -> some View {
    if !reports.isEmpty {
      NavigationLink(value: GlobalNavigationDestination.anodyneLinks(title: "\(source) Reports", links: reports)) {
        LabeledContent(source, value: reports.count.formatted())
      }
    }
  }
}

// Where the screen's information comes from, with links to the full pages. Takes the loaded data as a
// value, so the section redraws when it arrives.
struct SourcesSection: View {
  var psychonautWikiURL: URL?
  let anodyne: AnodyneSubstance?
  var isMissingOnAnodyne = false

  var body: some View {
    Section {
      if let psychonautWikiURL {
        NavigationLink(value: GlobalNavigationDestination.webView(articleURL: psychonautWikiURL)) {
          Label("PsychonautWiki Article", systemImage: "doc.text")
        }
      }
      if let anodyne {
        NavigationLink(value: GlobalNavigationDestination.webView(articleURL: anodyne.pageURL)) {
          Label("AnodyneWiki Page", systemImage: "books.vertical")
        }
        if !anodyne.references.isEmpty {
          NavigationLink(value: GlobalNavigationDestination.anodyneLinks(title: "References", links: anodyne.references)) {
            LabeledContent("References", value: anodyne.references.count.formatted())
          }
        }
      }
    } header: {
      Text("Sources")
    } footer: {
      if isMissingOnAnodyne {
        Text("AnodyneWiki has no page for this substance.")
      } else if anodyne != nil {
        Text("AnodyneWiki aggregates many sources; its content is in the public domain unless noted otherwise.")
      }
    }
  }
}

// MARK: - Rows

// The dose tiers of one route from logged doses, laid out like PsychonautWiki's ranges in the dose section
struct AnodyneDosingRow: View {
  let dosing: AnodyneSubstance.Dosing

  static let disclaimer =
    "From AnodyneWiki, derived statistically from logged doses (DBI-IGS). These are averages, not recommendations."

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(dosing.route?.rawValue.localizedCapitalized ?? dosing.method)
          .font(.headline)
        Spacer()
        Text("^[\(dosing.totalEntries) log](inflect: true)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      AnodyneDoseLadder(dosing: dosing)
    }
  }
}

// AnodyneWiki's five tiers in the style of PsychonautWiki's dose row (DoseClassificationRow): the doses where
// tiers meet, each range named below a dash between them. Light has no lower bound, so it opens the row
// as "≤ light", and heavy ends where extreme starts.
struct AnodyneDoseLadder: View {
  let dosing: AnodyneSubstance.Dosing

  private enum Item: Hashable {
    case dose(String, from: Color, to: Color)
    case range(symbol: String, name: String, color: Color)
  }

  private var items: [Item] {
    var items: [Item] = []
    let tiers: [(name: String, color: Color, tier: AnodyneSubstance.Tier?)] = [
      ("light", DoseRangeType.light.color, dosing.light),
      ("common", DoseRangeType.common.color, dosing.common),
      ("strong", DoseRangeType.strong.color, dosing.strong),
      ("heavy", DoseRangeType.heavy.color, dosing.heavy),
      ("extreme", .purple, dosing.extreme),
    ]
    var previousColor: Color?
    for (name, color, tier) in tiers {
      guard let tier else { continue }
      if let previousColor {
        items.append(.dose(tier.lower.formatted(), from: previousColor, to: color))
        items.append(.range(symbol: "-", name: name, color: color))
      } else {
        // The first tier has no lower bound
        items.append(.range(symbol: "≤", name: name, color: color))
      }
      previousColor = color
    }
    return items
  }

  private var doseFont: Font {
    items.contains { item in
      if case let .dose(text, _, _) = item { text.count >= 4 } else { false }
    } ? .footnote : .body
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        Spacer(minLength: 0)
        switch item {
        case let .dose(text, from, to):
          Text(text)
            .foregroundLinearGradient(colors: [from, to])
            .font(doseFont)
        case let .range(symbol, name, color):
          VStack {
            Text(symbol)
              .font(doseFont)
            Text(name)
              .fontWidth(.condensed)
              .lineLimit(1)
              .font(.footnote)
          }
          .foregroundColor(color)
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
      Text(dosing.unit ?? "")
        .font(doseFont)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let light = dosing.light.map { "Light up to \($0.upper.formatted()) \($0.unit)" }
    let others = [("Common", dosing.common), ("Strong", dosing.strong), ("Heavy", dosing.heavy), ("Extreme", dosing.extreme)]
      .compactMap { name, tier in
        tier.map { "\(name) from \($0.lower.formatted()) \($0.unit)" }
      }
    return ([light].compactMap { $0 } + others).joined(separator: ", ")
  }
}

// A titled text that is read in full by expanding it, for the long literature texts
struct ExpandableText: View {
  let title: String
  let text: String

  var body: some View {
    DisclosureGroup(title) {
      Text(text)
        .font(.subheadline)
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }
  }
}

// A title above a value that may run over several lines
struct DetailRow: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(text)
    }
    .accessibilityElement(children: .combine)
  }
}

struct ChipList: View {
  let items: [String]

  var body: some View {
    WrappingHStack(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
      ForEach(items, id: \.self) { item in
        Chip(name: item)
      }
    }
  }
}
