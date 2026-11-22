import SwiftUI

// Everything the app takes from a substance's AnodyneWiki page, laid out like FreakLog's own substance
// screens. Substances that are neither in PsychonautWiki nor custom yet can be added as custom substances.
struct AnodyneSubstanceScreen: View {
  let title: String
  @StateObject private var model: AnodyneLoadModel
  @State private var isShowingAddSheet = false
  @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
  private var customSubstances: FetchedResults<CustomSubstance>

  init(title: String) {
    self.title = title
    _model = StateObject(wrappedValue: AnodyneLoadModel(name: title))
  }

  var body: some View {
    Group {
      switch model.phase {
      case .idle, .loading:
        ProgressView()
      case .notFound:
        Text("AnodyneWiki has no page for \(title).")
          .foregroundStyle(.secondary)
      case .failed:
        VStack(spacing: 12) {
          Text("AnodyneWiki couldn't be loaded.")
            .foregroundStyle(.secondary)
          Button("Try Again") {
            Task { await model.load() }
          }
        }
      case let .found(substance):
        List {
          if let existingDestination = existingDestination(for: substance) {
            Section {
              NavigationLink(value: existingDestination) {
                Label("Open in FreakLog", systemImage: "arrow.forward.circle")
              }
            } footer: {
              Text("FreakLog already has this substance.")
            }
          }
          overviewSection(substance)
          AnodyneTopicSections(anodyne: substance, userNotes: model.userNotes)
          SourcesSection(anodyne: substance)
        }
        .sheet(isPresented: $isShowingAddSheet) {
          AddAnodyneSubstanceSheet(substance: substance)
        }
      }
    }
    .navigationTitle(model.substance?.commonName ?? title)
    .toolbar {
      if let substance = model.substance, existingDestination(for: substance) == nil {
        ToolbarItem(placement: .primaryAction) {
          Button("Add") {
            isShowingAddSheet = true
          }
        }
      }
    }
    .task {
      // Opening the screen asks for the substance, so it is loaded even without automatic loading
      await model.start(loadingIfNotCached: true)
    }
  }

  // The app's own substance of the same name, if there is one
  private func existingDestination(for substance: AnodyneSubstance) -> GlobalNavigationDestination? {
    for name in [substance.title] + substance.abbreviations {
      if let pwSubstance = SubstanceRepo.shared.getSubstance(name: name) {
        return .substance(substance: pwSubstance)
      }
      if let custom = customSubstances.first(where: { $0.nameUnwrapped.caseInsensitiveCompare(name) == .orderedSame }) {
        return .customSubstance(customSubstance: custom)
      }
    }
    return nil
  }

  @ViewBuilder
  private func overviewSection(_ substance: AnodyneSubstance) -> some View {
    let names = (substance.abbreviations + substance.slang + substance.aliases)
      .uniqued()
      .filter { $0.caseInsensitiveCompare(substance.commonName) != .orderedSame }
    if !substance.classes.isEmpty || !names.isEmpty || substance.title != substance.commonName {
      Section("Overview") {
        if substance.title != substance.commonName {
          DetailRow(title: "Name", text: substance.title)
        }
        if !substance.classes.isEmpty {
          ChipList(items: substance.classes)
        }
        if !names.isEmpty {
          DetailRow(title: "Also Known As", text: names.prefix(12).joined(separator: ", "))
        }
      }
    }
  }
}

// Creates a custom substance from an AnodyneWiki substance, with a dose override for every route it has
// dose tiers for and the categories matching its classes
private struct AddAnodyneSubstanceSheet: View {
  let substance: AnodyneSubstance
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var toastViewModel: ToastViewModel
  @State private var name = ""
  @State private var units = ""

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isNameTaken: Bool {
    SubstanceRepo.shared.getSubstance(name: trimmedName) != nil
      || PersistenceController.shared.getCustomSubstance(name: trimmedName) != nil
  }

  // The first dose data of each route the app knows
  private var dosingByRoute: [(route: AdministrationRoute, dosing: AnodyneSubstance.Dosing)] {
    var seen = Set<AdministrationRoute>()
    return substance.dosing.compactMap { dosing in
      guard let route = dosing.route, seen.insert(route).inserted else { return nil }
      return (route, dosing)
    }
  }

  private var categories: [String] {
    let known = SubstanceRepo.shared.categories.map(\.name)
    let classes = Set(substance.classes.map { $0.lowercased() })
    return known.filter { classes.contains($0.lowercased()) }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .autocorrectionDisabled()
        } header: {
          Text("Name")
        } footer: {
          if isNameTaken {
            Text("A substance is already called \(trimmedName).")
              .foregroundColor(.red)
          }
        }
        Section("Units") {
          TextField("Units", text: $units)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        Section {
          if dosingByRoute.isEmpty {
            Text("AnodyneWiki has no dose data for this substance.")
              .foregroundStyle(.secondary)
          }
          ForEach(dosingByRoute, id: \.route) { item in
            LabeledContent(
              item.route.rawValue.localizedCapitalized,
              value: item.dosing.common.map { "common from \($0.lower.formatted()) \($0.unit)" } ?? "dose tiers"
            )
          }
          if !categories.isEmpty {
            LabeledContent("Categories", value: categories.joined(separator: ", "))
          }
        } header: {
          Text("Taken from AnodyneWiki")
        } footer: {
          Text("Each route's common, strong and heavy doses are set where AnodyneWiki's tiers start. You can edit them later.")
        }
      }
      .navigationTitle("Add Custom Substance")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add", action: add)
            .disabled(trimmedName.isEmpty || units.isEmpty || isNameTaken)
        }
      }
      .onAppear {
        name = substance.commonName
        units = substance.dosing.lazy.compactMap(\.unit).first ?? UnitPickerOptions.mg.rawValue
      }
    }
  }

  private func add() {
    let context = PersistenceController.shared.viewContext
    let customSubstance = CustomSubstance(context: context)
    customSubstance.name = trimmedName
    customSubstance.units = units
    customSubstance.explanation = "From AnodyneWiki: \(substance.title)"
    for item in dosingByRoute {
      item.dosing.doseValues(for: item.route)
        .insert(into: context, substanceName: trimmedName)
        .customSubstance = customSubstance
    }
    PersistenceController.shared.saveViewContext()
    if !categories.isEmpty {
      PersistenceController.shared.setSubstanceOverride(for: trimmedName, displayName: nil, categories: categories)
    }
    toastViewModel.showSuccessToast(message: "Substance Added")
    dismiss()
  }
}

extension Color {
  // AnodyneWiki writes reagent colors as #rrggbb
  init(anodyneHex hex: String) {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(digits, radix: 16) ?? 0
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}
