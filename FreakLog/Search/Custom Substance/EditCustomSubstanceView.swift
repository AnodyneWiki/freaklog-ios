import CoreData
import SwiftUI

struct EditCustomSubstanceView: View {
  @ObservedObject var customSubstance: CustomSubstance
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var toastViewModel: ToastViewModel
  @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
  private var customSubstances: FetchedResults<CustomSubstance>
  @State private var isShowingConfirmation = false
  @State private var units = ""
  @State private var name = ""
  @State private var description = ""

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Renaming onto another substance's name would merge their ingestions and data
  private var isNameTaken: Bool {
    guard trimmedName != customSubstance.nameUnwrapped else { return false }
    return SubstanceRepo.shared.substances.contains { SimilarSubstanceNames.isSameName($0.name, trimmedName) }
      || customSubstances.contains {
        $0.objectID != customSubstance.objectID && SimilarSubstanceNames.isSameName($0.nameUnwrapped, trimmedName)
      }
  }

  var body: some View {
    List {
      Section {
        TextField("Name", text: $name)
      } header: {
        Text("Name")
      } footer: {
        if isNameTaken {
          Text("Another substance is already called \(trimmedName). The name is kept as \(customSubstance.nameUnwrapped).")
            .foregroundColor(.red)
        } else {
          Text("Renaming also renames your ingestions, units and data of this substance.")
        }
      }
      Section("Description") {
        TextField("Description", text: $description)
      }
      Section("Units") {
        TextField("Units", text: $units)
      }
      Section {
        NavigationLink("Categories") {
          EditCategoriesScreen(substanceName: customSubstance.nameUnwrapped)
        }
      }
      Section {
        CustomRoaRouteList(substanceName: customSubstance.nameUnwrapped, customSubstance: customSubstance)
      } header: {
        Text("Routes (Dose & Duration)")
      } footer: {
        Text("Add dose ranges and timing data per administration route.")
      }
      if let file = try? JournalPreset(customSubstance: .init(customSubstance)).exportFile() {
        Section {
          JournalPresetFileShare(file: file, name: customSubstance.nameUnwrapped)
        } footer: {
          Text("Shares the saved definition and its route information.")
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .confirmationDialog(
      "Are you sure you want to delete this substance?",
      isPresented: $isShowingConfirmation
    ) {
      Button("Delete Substance", role: .destructive) {
        dismiss()
        let name = customSubstance.nameUnwrapped
        PersistenceController.shared.viewContext.delete(customSubstance)
        // Its display name and categories go too, unless they belong to a PsychonautWiki substance of that name
        if SubstanceRepo.shared.getSubstance(name: name) == nil {
          PersistenceController.shared.setSubstanceOverride(for: name, displayName: nil, categories: nil)
        }
        PersistenceController.shared.saveViewContext()
      }
      Button("Cancel", role: .cancel) {}
    }
    .onAppear {
      name = customSubstance.nameUnwrapped
      units = customSubstance.unitsUnwrapped
      description = customSubstance.explanationUnwrapped
    }
    .onDisappear {
      guard !units.isEmpty else { return }
      let oldName = customSubstance.nameUnwrapped
      let newName = trimmedName.isEmpty || isNameTaken ? oldName : trimmedName
      guard !customSubstance.isDeleted,
            newName != oldName || units != customSubstance.unitsUnwrapped || description != customSubstance.explanationUnwrapped
      else { return }
      do {
        let context = try PersistenceController.shared.journalEditContext()
        let updated = try PersistenceController.journalObject(customSubstance, in: context)
        updated.name = newName
        updated.units = units
        updated.explanation = description
        if newName != oldName {
          try PersistenceController.renameSubstance(from: oldName, to: newName, in: context)
        }
        try context.save()
      } catch {
        toastViewModel.showErrorToast(message: "Couldn't save substance changes")
      }
    }
    .toolbar {
      ToolbarItem {
        Button {
          isShowingConfirmation.toggle()
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .foregroundColor(.red)
      }
    }
    .navigationTitle(customSubstance.nameUnwrapped)
  }
}

struct SimilarCustomSubstancesScreen: View {
  @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
  private var customSubstances: FetchedResults<CustomSubstance>

  private var pairs: [SimilarCustomSubstancePair] {
    let groups = Dictionary(grouping: customSubstances, by: \.nameUnwrapped)
    let candidates = customSubstances.filter {
      groups[$0.nameUnwrapped]?.count == 1 && SubstanceRepo.shared.getSubstance(name: $0.nameUnwrapped) == nil
    }
    return candidates.indices.flatMap { index in
      candidates.dropFirst(index + 1).compactMap { other in
        let first = candidates[index]
        guard SimilarSubstanceNames.distance(first.nameUnwrapped, other.nameUnwrapped) != nil else { return nil }
        return SimilarCustomSubstancePair(first: first, second: other)
      }
    }
  }

  var body: some View {
    List {
      let matches = pairs
      if matches.isEmpty {
        Text("No similar custom substance names found").foregroundStyle(.secondary)
      }
      ForEach(matches) { pair in
        NavigationLink {
          CustomSubstanceMergeReview(pair: pair)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(pair.first.nameUnwrapped)
            Text(pair.second.nameUnwrapped).foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Similar Names")
  }
}

struct SimilarCustomSubstancePair: Identifiable {
  let first: CustomSubstance
  let second: CustomSubstance

  var id: String {
    first.objectID.uriRepresentation().absoluteString + "|" + second.objectID.uriRepresentation().absoluteString
  }
}

private struct CustomSubstanceMergeReview: View {
  let pair: SimilarCustomSubstancePair
  @Environment(\.dismiss) private var dismiss
  @State private var preview: CustomSubstanceMergePreview?
  @State private var selection: [String: Int] = [:]
  @State private var isConfirming = false
  @State private var failure: String?

  var body: some View {
    Form {
      if let preview {
        Section("Substances") {
          ForEach(preview.definitions.indices, id: \.self) { index in
            let definition = preview.definitions[index]
            VStack(alignment: .leading, spacing: 4) {
              Text(definition.name).font(.headline)
              if !definition.units.isEmpty { Text("Default units: \(definition.units)").foregroundStyle(.secondary) }
              if !definition.description.isEmpty { Text(definition.description).foregroundStyle(.secondary) }
            }
          }
          Picker("Name to Keep", selection: choice("name")) {
            names(in: preview)
          }
        }
        Section("Records to Combine") {
          LabeledContent("Ingestions", value: preview.ingestionCount.formatted())
          LabeledContent("Custom Units", value: preview.unitCount.formatted())
          LabeledContent("Formulations", value: preview.formulationCount.formatted())
          LabeledContent("Saved Routes", value: preview.routeCount.formatted())
        }
        if !preview.conflicts.isEmpty {
          Section {
            ForEach(preview.conflicts, id: \.id) { conflict in
              Picker(conflict.label, selection: choice(conflict.id)) {
                Text(conflict.values[0]).tag(0)
                Text(conflict.values[1]).tag(1)
              }
            }
          } header: {
            Text("Choose Which Values to Keep")
          }
        }
        Section {
          Button("Merge Substances", role: .destructive) { isConfirming = true }
        } footer: {
          Text("The journal will use one substance name. Recorded amounts and units stay as entered.")
        }
      }
      if let failure {
        Text(failure).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Review Merge")
    .task {
      do {
        let context = try PersistenceController.shared.journalEditContext()
        let review = try CustomSubstanceMergeRecords.load(pair, in: context).preview
        selection["name"] = review.definitions[0].ingestionCount >= review.definitions[1].ingestionCount ? 0 : 1
        preview = review
      } catch {
        failure = error.localizedDescription
      }
    }
    .confirmationDialog("Combine these substances?", isPresented: $isConfirming, titleVisibility: .visible) {
      Button("Merge Substances", role: .destructive, action: merge)
      Button("Cancel", role: .cancel) {}
    }
  }

  private func choice(_ id: String) -> Binding<Int> {
    Binding(get: { selection[id] ?? selection["name"] ?? 0 }, set: { selection[id] = $0 })
  }

  private func names(in preview: CustomSubstanceMergePreview) -> some View {
    ForEach(preview.definitions.indices, id: \.self) { index in
      Text(preview.definitions[index].name).tag(index)
    }
  }

  private func merge() {
    guard let preview else { return }
    do {
      let context = try PersistenceController.shared.journalEditContext()
      let records = try CustomSubstanceMergeRecords.load(pair, in: context)
      guard records.preview == preview else { throw SimilarSubstanceError.changed }
      let changed = try records.merge(selection: selection, in: context)
      if !changed.isEmpty { IngestionSaving.didSave(changed, newIngestions: []) }
      dismiss()
    } catch {
      failure = error.localizedDescription
    }
  }
}

struct CustomSubstanceMergePreview: Equatable {
  struct Conflict {
    let id: String
    let label: String
    let values: [String]
  }

  struct Definition: Equatable {
    let name: String
    let units: String
    let description: String
    let color: String?
    let hidesTimeline: Bool
    let overrides: SubstanceOverrideCache.Entry
    let routes: [String: [CustomRoaCodable]]
    let ingestionCount: Int
    let unitCount: Int
  }

  let definitions: [Definition]
  let formulationCount: Int

  var ingestionCount: Int { definitions.reduce(0) { $0 + $1.ingestionCount } }
  var unitCount: Int { definitions.reduce(0) { $0 + $1.unitCount } }
  var routeCount: Int { Set(definitions.flatMap { $0.routes.keys }).count }

  var conflicts: [Conflict] {
    let first = definitions[0]
    let second = definitions[1]
    var conflicts: [Conflict] = []
    func add(_ id: String, _ label: String, _ left: String?, _ right: String?) {
      guard let left, let right, left != right else { return }
      conflicts.append(Conflict(id: id, label: label, values: [left, right]))
    }
    add("units", "Default Units", first.units.isEmpty ? nil : first.units, second.units.isEmpty ? nil : second.units)
    if first.description != second.description {
      add("description", "Description", first.description.isEmpty ? nil : first.name, second.description.isEmpty ? nil : second.name)
    }
    if first.color != second.color {
      add("color", "Journal Color", first.color.map { "\(first.name) · \($0)" }, second.color.map { "\(second.name) · \($0)" })
    }
    if first.hidesTimeline != second.hidesTimeline {
      add("visibility", "Timeline Visibility",
          first.hidesTimeline ? String(localized: "Hidden") : String(localized: "Visible"),
          second.hidesTimeline ? String(localized: "Hidden") : String(localized: "Visible"))
    }
    add("displayName", "Display Name", first.overrides.displayName, second.overrides.displayName)
    add("categories", "Categories",
        first.overrides.categories?.isEmpty == true ? String(localized: "None") : first.overrides.categories?.joined(separator: ", "),
        second.overrides.categories?.isEmpty == true ? String(localized: "None") : second.overrides.categories?.joined(separator: ", "))
    add("primaryTag", "Primary Tag", first.overrides.tags.primary, second.overrides.tags.primary)
    for route in Set(first.routes.keys).intersection(second.routes.keys).sorted()
      where first.routes[route] != second.routes[route] {
      add("route:\(route)", route.localizedCapitalized, first.name, second.name)
    }
    return conflicts
  }
}

@MainActor
struct CustomSubstanceMergeRecords {
  struct Substance {
    let custom: CustomSubstance
    let ingestions: [Ingestion]
    let units: [CustomUnit]
    let components: [FormulationComponent]
    let companions: [SubstanceCompanion]
    let overrides: [SubstanceOverride]
    let routes: [String: [CustomRoa]]

    private var routeValues: [String: [CustomRoaCodable]] {
      routes.mapValues { rows in
        rows.map { roa in
          var values = roa.values
          if values.doseUnits?.isEmpty != false {
            values.doseUnits = roa.roaDose?.units
          }
          return values
        }
      }
    }

    var definition: CustomSubstanceMergePreview.Definition {
      CustomSubstanceMergePreview.Definition(
        name: custom.nameUnwrapped,
        units: custom.unitsUnwrapped,
        description: custom.explanationUnwrapped,
        color: companions.first?.color.rawValue,
        hidesTimeline: companions.contains(where: \.isHiddenInTimeline),
        overrides: overrides.reduce(.init(displayName: nil, categories: nil)) { $0.merged($1.entry) },
        routes: routeValues,
        ingestionCount: ingestions.count,
        unitCount: units.count
      )
    }

    init(_ custom: CustomSubstance, in context: NSManagedObjectContext) throws {
      self.custom = custom
      let name = custom.nameUnwrapped
      let namePredicate = NSPredicate(format: "substanceName == %@", name)
      let ingestionRequest = PersistenceController.historyIngestionsRequest(for: name)
      let unitRequest = CustomUnit.fetchRequest()
      unitRequest.predicate = namePredicate
      let componentsRequest = FormulationComponent.fetchRequest()
      componentsRequest.predicate = namePredicate
      let companionsRequest = SubstanceCompanion.fetchRequest()
      companionsRequest.predicate = namePredicate
      let roas = try context.fetch(PersistenceController.customRoasRequest(for: name))
      ingestions = try context.fetch(ingestionRequest)
      units = try context.fetch(unitRequest)
      components = try context.fetch(componentsRequest)
      companions = try context.fetch(companionsRequest).sorted {
        ($0.colorAsText ?? "") < ($1.colorAsText ?? "")
      }
      overrides = try context.fetch(PersistenceController.substanceOverridesRequest(for: name))
      routes = Dictionary(grouping: roas) { $0.administrationRoute ?? "" }
    }
  }

  let substances: [Substance]

  var preview: CustomSubstanceMergePreview {
    CustomSubstanceMergePreview(
      definitions: substances.map(\.definition),
      formulationCount: Set(substances.flatMap { $0.components.compactMap { $0.formulation?.objectID } }).count
    )
  }

  static func load(_ pair: SimilarCustomSubstancePair, in context: NSManagedObjectContext) throws -> Self {
    let custom: [CustomSubstance] = try [pair.first, pair.second].map {
      try PersistenceController.journalObject($0, in: context)
    }
    let names = custom.map(\.nameUnwrapped)
    let request = PersistenceController.customSubstancesRequest()
    request.predicate = NSPredicate(format: "name IN %@", names)
    guard names[0] != names[1],
          names.allSatisfy({ SubstanceRepo.shared.getSubstance(name: $0) == nil }),
          try context.fetch(request).count == 2
    else { throw SimilarSubstanceError.changed }
    return try Self(substances: custom.map { try Substance($0, in: context) })
  }

  func merge(selection: [String: Int], in context: NSManagedObjectContext) throws -> [Ingestion] {
    let chosen = selection["name"] ?? 0
    let removed = 1 - chosen
    let retained = substances[chosen].custom
    let duplicate = substances[removed].custom
    let name = retained.nameUnwrapped
    let definitions = substances.map(\.definition)
    func value<T>(_ id: String, _ keyPath: KeyPath<CustomSubstanceMergePreview.Definition, T?>) -> T? {
      let first = selection[id] ?? chosen
      return definitions[first][keyPath: keyPath] ?? definitions[1 - first][keyPath: keyPath]
    }

    let unitIndex = selection["units"] ?? chosen
    let descriptionIndex = selection["description"] ?? chosen
    let preferredUnits = definitions[unitIndex].units
    let preferredDescription = definitions[descriptionIndex].description
    retained.units = preferredUnits.isEmpty ? definitions[1 - unitIndex].units : preferredUnits
    retained.explanation = preferredDescription.isEmpty ? definitions[1 - descriptionIndex].description : preferredDescription

    let colorIndex = selection["color"] ?? chosen
    let companion = substances[colorIndex].companions.first ?? substances[1 - colorIndex].companions.first
    companion?.substanceName = name
    companion?.isHiddenInTimeline = definitions[selection["visibility"] ?? chosen].hidesTimeline
    for entry in substances.flatMap(\.ingestions) {
      entry.substanceName = name
      if let companion {
        entry.substanceCompanion = companion
      }
    }
    for extra in substances.flatMap(\.companions) where extra != companion {
      // Preserve any incorrectly-linked legacy records when collapsing the color rows.
      for ingestion in extra.ingestionsUnwrapped {
        ingestion.substanceCompanion = companion
      }
      context.delete(extra)
    }

    for unit in substances[removed].units { unit.substanceName = name }
    for component in substances[removed].components { component.substanceName = name }

    for route in Set(definitions.flatMap { $0.routes.keys }) {
      let preferred = selection["route:\(route)"] ?? chosen
      let keep = substances[preferred].routes[route]?.isEmpty == false ? preferred : 1 - preferred
      for (index, substance) in substances.enumerated() {
        for (offset, row) in (substance.routes[route] ?? []).enumerated() {
          if index == keep {
            row.substanceName = name
            row.customSubstance = retained
            row.doseUnits = definitions[index].routes[route]?[offset].doseUnits
          } else {
            context.delete(row)
          }
        }
      }
    }

    let tags = definitions[chosen].overrides.tags.names + definitions[removed].overrides.tags.names
    let tagOwner = selection["primaryTag"] ?? chosen
    let primary = definitions[tagOwner].overrides.tags.primary ?? definitions[1 - tagOwner].overrides.tags.primary
    let displayName = value("displayName", \.overrides.displayName)
    PersistenceController.applySubstanceOverride(
      .init(
        displayName: displayName == name ? nil : displayName,
        categories: value("categories", \.overrides.categories),
        tags: PersonalSubstanceTags(tags, primary: primary)
      ),
      for: name,
      existing: substances[chosen].overrides + substances[removed].overrides,
      in: context
    )
    context.delete(duplicate)
    let changed = substances.flatMap(\.ingestions).filter(\.hasChanges)
    try PersistenceController.saveJournalChanges(in: context)
    return changed
  }
}
