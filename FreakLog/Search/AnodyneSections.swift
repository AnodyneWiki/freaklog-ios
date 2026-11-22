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

  @Published private(set) var phase = Phase.idle
  // What AnodyneWiki's users wrote about the substance on their userpages
  @Published private(set) var userNotes: [AnodyneUserNote] = []
  let name: String
  let otherNames: [String]

  init(name: String, otherNames: [String] = []) {
    self.name = name
    self.otherNames = otherNames
  }

  var substance: AnodyneSubstance? {
    if case let .found(substance) = phase { substance } else { nil }
  }

  func start(loadingIfNotCached: Bool = AnodyneClient.isAutomaticLoadingEnabled) async {
    guard phase == .idle else { return }
    if let cached = await AnodyneClient.shared.cachedLookup(for: name) {
      phase = Self.makePhase(for: cached)
      await loadUserNotes()
    } else if loadingIfNotCached {
      await load()
    }
  }

  func load() async {
    phase = .loading
    do {
      phase = Self.makePhase(for: try await AnodyneClient.shared.lookup(name, otherNames: otherNames))
    } catch {
      phase = .failed
    }
    await loadUserNotes()
  }

  // Userpages name substances by their AnodyneWiki title, sometimes by an abbreviation
  private func loadUserNotes() async {
    guard let substance else { return }
    let names = [substance.title, name] + substance.abbreviations
    userNotes = (try? await AnodyneClient.shared.userNotes(matching: names)) ?? []
  }

  private static func makePhase(for lookup: AnodyneClient.Lookup) -> Phase {
    switch lookup {
    case let .found(substance): .found(substance)
    case .notFound: .notFound
    }
  }
}

// Offers to load AnodyneWiki's data while it isn't there. Once loaded, the data shows in the
// screen's topics, so this section disappears.
struct AnodyneLoadSection: View {
  @ObservedObject var model: AnodyneLoadModel

  var body: some View {
    switch model.phase {
    case .idle:
      Section {
        Button {
          Task { await model.load() }
        } label: {
          Label("More from AnodyneWiki", systemImage: "books.vertical")
        }
      } footer: {
        Text("Adds logged doses, legal status, reagent tests, experience reports and more from anodyne.wiki.")
      }
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
        HStack {
          Text("AnodyneWiki couldn't be loaded.")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Try Again") {
            Task { await model.load() }
          }
        }
      }
    case .found, .notFound:
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

// AnodyneWiki's duration texts, for substances without a PsychonautWiki timeline
struct AnodyneDurationSection: View {
  let anodyne: AnodyneSubstance

  var body: some View {
    if anodyne.durationOfAction != nil || anodyne.halfLife != nil {
      Section("Duration") {
        AnodyneDurationRows(anodyne: anodyne)
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
          NavigationLink {
            AnodyneUserNoteScreen(note: note)
          } label: {
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

  var body: some View {
    if isIncludingSharedTopics {
      EffectsSection(summary: nil, anodyne: anodyne)
    }
    AnodyneLoggedDosesSection(anodyne: anodyne)
    if isIncludingSharedTopics {
      AnodyneDurationSection(anodyne: anodyne)
      InteractionsSection(substance: nil, anodyne: anodyne)
      ToxicitySection(substance: nil, anodyne: anodyne)
    }
    AnodyneWarningsSection(anodyne: anodyne)
    AnodyneReagentsSection(anodyne: anodyne)
    AnodyneLegalStatusSection(anodyne: anodyne)
    AnodynePharmacologySection(anodyne: anodyne)
    AnodyneReportsSection(anodyne: anodyne, userNotes: userNotes)
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
        Text("Logged Doses")
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

  // One row per source, so the page stays short however many reports there are
  var body: some View {
    if !userNotes.isEmpty || !anodyne.erowidReports.isEmpty || !anodyne.redditReports.isEmpty {
      Section("Experience Reports") {
        if !userNotes.isEmpty {
          NavigationLink {
            AnodyneUserNotesScreen(notes: userNotes)
          } label: {
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
      NavigationLink {
        List(reports, id: \.url) { report in
          NavigationLink(report.title, value: GlobalNavigationDestination.webView(articleURL: report.url))
        }
        .navigationTitle("\(source) Reports")
      } label: {
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
          NavigationLink {
            List(anodyne.references, id: \.url) { reference in
              NavigationLink(reference.title, value: GlobalNavigationDestination.webView(articleURL: reference.url))
            }
            .navigationTitle("References")
          } label: {
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

// The dose tiers of one route, from logged doses: the common range, expanding to every tier
struct AnodyneDosingRow: View {
  let dosing: AnodyneSubstance.Dosing

  static let disclaimer =
    "From AnodyneWiki, derived statistically from logged doses (DBI-IGS). These are averages, not recommendations."

  var body: some View {
    DisclosureGroup {
      tierRow("Light", color: DoseRangeType.light.color, text: dosing.light.map { "up to \(amount($0.upper, $0))" })
      tierRow("Common", color: DoseRangeType.common.color, text: dosing.common.map(range))
      tierRow("Strong", color: DoseRangeType.strong.color, text: dosing.strong.map(range))
      tierRow("Heavy", color: DoseRangeType.heavy.color, text: dosing.heavy.map(range))
      tierRow("Extreme", color: .purple, text: dosing.extreme.map { "\(amount($0.lower, $0)) and more" })
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(dosing.route?.rawValue.localizedCapitalized ?? dosing.method)
          Text("^[\(dosing.totalEntries) log](inflect: true)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let common = dosing.common {
          Text("Common \(range(common))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    }
  }

  @ViewBuilder
  private func tierRow(_ name: String, color: Color, text: String?) -> some View {
    if let text {
      HStack(spacing: 8) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
          .accessibilityHidden(true)
        Text(name)
        Spacer()
        Text(text)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.subheadline)
      .accessibilityElement(children: .combine)
    }
  }

  private func range(_ tier: AnodyneSubstance.Tier) -> String {
    tier.lower == tier.upper
      ? amount(tier.lower, tier)
      : "\(tier.lower.formatted())–\(amount(tier.upper, tier))"
  }

  private func amount(_ value: Double, _ tier: AnodyneSubstance.Tier) -> String {
    "\(value.formatted()) \(tier.unit)"
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
