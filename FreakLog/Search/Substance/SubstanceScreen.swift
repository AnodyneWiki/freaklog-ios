import CoreData
import SwiftUI

struct SubstanceScreen: View {
  let substance: Substance
  @AppStorage(PersistenceController.anodyneInstanceURLKey) private var instanceURL = ""

  @State private var isShowingCustomizeSheet = false
  @StateObject private var anodyneModel: AnodyneLoadModel
  @FetchRequest private var customRoas: FetchedResults<CustomRoa>
  // Redraws the screen when the user's name or categories for the substance change
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substance: Substance) {
    self.substance = substance
    _anodyneModel = StateObject(wrappedValue: AnodyneLoadModel(name: substance.name, otherNames: substance.commonNames))
    _customRoas = FetchRequest(fetchRequest: PersistenceController.customRoasRequest(for: substance.name))
    _overrides = FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest(for: substance.name))
  }

  // Each topic shows PsychonautWiki's information, completed with AnodyneWiki's once it is loaded
  var body: some View {
    let anodyne = substance.usesWikiReferences ? anodyneModel.substance : nil
    List {
      overviewSection(anodyne: anodyne)
      SubstanceJournalLinks(substanceName: substance.name)
      if substance.usesWikiReferences {
        AnodyneLoadStatus(model: anodyneModel)
      }
      EffectsSection(summary: substance.effectsSummary, anodyne: anodyne)
      if let anodyne {
        AnodyneReportsSection(anodyne: anodyne, userNotes: anodyneModel.userNotes)
      }
      Group {
        let hasDoses = substance.dosageRemark != nil || !substance.doseInfos.isEmpty
          || customRoas.contains(where: { $0.roaDose != nil }) || anodyne?.dosing.isEmpty == false
        let hasDurations = !substance.durationInfos.isEmpty || customRoas.contains(where: { $0.roaDuration != nil })
          || (anodyne != nil && hasAnodyneTimings)
        if hasDoses || hasDurations {
          SubstanceSourceComparisonLink(
            substanceName: substance.name,
            psychonautWiki: substance.usesWikiReferences ? substance : nil,
            anodyne: anodyne,
            isMissingOnAnodyne: anodyneModel.phase == .notFound
          )
        }
        if hasDoses {
          DosesSection(substance: substance, anodyne: anodyne)
        }
        if hasDurations {
          DurationSection(substance: substance, anodyne: anodyne)
        } else if let anodyne {
          AnodyneDurationSection(anodyne: anodyne)
        }
        InteractionsSection(substance: substance, anodyne: anodyne)
        if substance.tolerance != nil || !substance.crossTolerances.isEmpty {
          ToleranceSection(substance: substance)
        }
        ToxicitySection(substance: substance, anodyne: anodyne)
      }
      Group {
        if let acute = substance.generalRisks {
          Section("Acute Risk") { Text(acute) }
        }
        if let longTerm = substance.longtermRisks {
          Section("Long-term Risk") { Text(longTerm) }
        }
        if let anodyne {
          AnodyneWarningsSection(anodyne: anodyne)
        }
        if !substance.saferUse.isEmpty {
          Section("Safer Use") {
            ForEach(substance.saferUse, id: \.self) { point in Text(point) }
          }
        }
        if let addictionPotential = substance.addictionPotential {
          Section("Addiction Potential") { Text(addictionPotential) }
        }
      }
      if let anodyne {
        AnodyneReagentsSection(anodyne: anodyne)
        AnodyneLegalStatusSection(anodyne: anodyne)
        AnodynePharmacologySection(anodyne: anodyne)
      }
      if substance.usesWikiReferences {
        SourcesSection(
          psychonautWikiURL: substance.url,
          anodyne: anodyne,
          isMissingOnAnodyne: anodyneModel.phase == .notFound
        )
      } else if let url = substance.url {
        Section("Sources") {
          NavigationLink(value: GlobalNavigationDestination.webView(articleURL: url)) {
            Label(substance.referenceSource.title, systemImage: "doc.text")
          }
        }
      }
    }
    .task(id: instanceURL) {
      if substance.usesWikiReferences {
        await anodyneModel.start()
      }
    }
    .toolbar {
      if substance.usesWikiReferences {
        ToolbarItem(placement: .topBarTrailing) {
          AnodyneSourcesMenu(model: anodyneModel, psychonautWikiURL: substance.url)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isShowingCustomizeSheet = true
        } label: {
          Label("Customize", systemImage: "slider.horizontal.3")
        }
      }
    }
    .sheet(isPresented: $isShowingCustomizeSheet) {
      SubstanceCustomizeSheet(substance: substance)
    }
    .navigationTitle(substance.displayName)
  }

  // AnodyneWiki's timings fill in routes without PsychonautWiki or custom durations
  private var hasAnodyneTimings: Bool {
    let timings = AnodyneFallbackStore.shared
    return !timings.routesWithTimings(for: substance.name).isEmpty
      || substance.roas.contains { timings.duration(for: substance.name, route: $0.name) != nil }
  }

  private func overviewSection(anodyne: AnodyneSubstance?) -> some View {
    let categories = PersistenceController.shared.categories(for: substance.name)
    let shownNames = Set([substance.name, substance.displayName, anodyne?.title].compactMap { $0?.lowercased() })
    let otherNames = (substance.commonNames + (anodyne?.abbreviations ?? []) + (anodyne?.slang ?? []))
      .uniqued()
      .filter { !shownNames.contains($0.lowercased()) }
    return Section {
      if let summary = substance.summary {
        Text(summary)
      }
      if !categories.isEmpty {
        CategorySection(categoryNames: categories)
      }
      if let anodyne {
        AnodyneChemistryRows(anodyne: anodyne, substanceName: substance.displayName)
      }
      if !otherNames.isEmpty {
        DetailRow(title: "Also Known As", text: otherNames.prefix(12).joined(separator: ", "))
      }
    } header: {
      Text("Overview")
    } footer: {
      if substance.hasUnapprovedWikiReference {
        Text("This information hasn't been approved by PsychonautWiki's moderators.")
      }
    }
  }
}

struct SubstanceJournalLinks: View {
  let substanceName: String
  @FetchRequest private var overrides: FetchedResults<SubstanceOverride>

  init(substanceName: String) {
    self.substanceName = substanceName
    _overrides = FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest(for: substanceName))
  }

  var body: some View {
    Section("Journal") {
      SubstanceTimelineVisibilityToggle(substanceName: substanceName)
      NavigationLink {
        EditPersonalTagsScreen(substanceName: substanceName)
      } label: {
        let tags = overrides.dropFirst().reduce(overrides.first?.personalTags ?? PersonalSubstanceTags()) {
          $0.merged($1.personalTags)
        }
        LabeledContent {
          if !tags.names.isEmpty {
            Text(tags.names.formatted(.list(type: .and)))
              .foregroundStyle(.secondary)
          }
        } label: {
          Label("Personal Tags", systemImage: "tag")
        }
      }
    }
  }
}

private struct EditPersonalTagsScreen: View {
  let substanceName: String
  @Environment(\.dismiss) private var dismiss
  @FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest())
  private var overrides: FetchedResults<SubstanceOverride>
  @State private var tags = PersonalSubstanceTags()
  @State private var newTag = ""
  @State private var saveFailed = false

  private var knownTags: [String] {
    PersonalSubstanceTags(overrides.flatMap { $0.personalTags.names }.sorted()).names
      .filter { !tags.contains($0) }
  }

  private var trimmedTag: String {
    newTag.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    Form {
      Section {
        TextField("New Tag", text: $newTag)
          .onSubmit { addTag(trimmedTag) }
        Button("Add Tag") { addTag(trimmedTag) }
          .disabled(trimmedTag.isEmpty || tags.contains(trimmedTag))
        if !knownTags.isEmpty {
          Menu("Choose Existing Tag") {
            ForEach(knownTags, id: \.self) { name in
              Button(name) { addTag(name) }
            }
          }
        }
      }
      if !tags.names.isEmpty {
        Section("Assigned Tags") {
          ForEach(tags.names, id: \.self) { tag in
            Text(tag)
          }
          .onDelete { offsets in
            var names = tags.names
            names.remove(atOffsets: offsets)
            tags = PersonalSubstanceTags(names, primary: tags.primary)
          }
        }
        Section {
          Picker("Primary Tag", selection: Binding(
            get: { tags.primary },
            set: { tags = PersonalSubstanceTags(tags.names, primary: $0) }
          )) {
            Text("None").tag(nil as String?)
            ForEach(tags.names, id: \.self) { name in
              Text(name).tag(Optional(name))
            }
          }
        }
      }
    }
    .navigationTitle("Personal Tags")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          do {
            try PersistenceController.shared.setPersonalTags(tags, for: substanceName)
            dismiss()
          } catch {
            saveFailed = true
          }
        }
      }
    }
    .onAppear {
      tags = PersistenceController.shared.personalTags(for: substanceName)
    }
    .alert("Couldn’t save tags", isPresented: $saveFailed) {
      Button("OK", role: .cancel) {}
    }
  }

  private func addTag(_ name: String) {
    guard !name.isEmpty else { return }
    tags = PersonalSubstanceTags(tags.names + [name], primary: tags.primary)
    newTag = ""
  }
}

// MARK: - SubstanceCustomizeSheet

struct SubstanceCustomizeSheet: View {
  let substance: Substance
  @Environment(\.dismiss) private var dismiss
  @State private var displayName = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField(substance.name, text: $displayName)
            .autocorrectionDisabled()
            .onSubmit(saveDisplayName)
        } header: {
          Text("Name")
        } footer: {
          Text(
            "Shown instead of \(substance.name) in your journal, stats, search and webhooks. "
              + "Your data stays linked to \(substance.name), so its dose, duration and interaction info keep working."
          )
        }
        Section {
          NavigationLink("Categories") {
            EditCategoriesScreen(substanceName: substance.name)
          }
        }
        Section {
          CustomRoaRouteList(substanceName: substance.name)
        } header: {
          Text("Override Dose & Duration")
        } footer: {
          if substance.usesWikiReferences {
            Text(
              "Routes open with the PsychonautWiki data filled in. "
                + "Your changes take priority over it in the timeline and dose display."
            )
          }
        }
      }
      .navigationTitle(substance.displayName)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear {
        displayName = PersistenceController.shared.substanceOverride(for: substance.name)?.displayName ?? ""
      }
      .onDisappear(perform: saveDisplayName)
    }
  }

  private func saveDisplayName() {
    let override = PersistenceController.shared.substanceOverride(for: substance.name)
    guard displayName != override?.displayName ?? "" else { return }
    PersistenceController.shared.setSubstanceOverride(
      for: substance.name,
      displayName: displayName,
      categories: override?.categories
    )
  }
}

#Preview {
  NavigationStack {
    SubstanceScreen(substance: SubstanceRepo.shared.getSubstance(name: "MDMA")!)
  }
}
