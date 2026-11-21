import SwiftUI
import WrappingHStack

// Everything the app takes from a substance's AnodyneWiki page. Substances that are neither in
// PsychonautWiki nor custom yet can be added as a custom substance with AnodyneWiki's doses.
struct AnodyneSubstanceScreen: View {
  let title: String
  @StateObject private var model: AnodyneLoadModel

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
        Button("Couldn't load AnodyneWiki. Try Again") {
          Task { await model.load() }
        }
      case let .found(substance):
        AnodyneSubstanceContent(substance: substance)
      }
    }
    .navigationTitle(title)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink("Page", value: GlobalNavigationDestination.webView(articleURL: AnodyneSubstance.pageURL(for: title)))
      }
    }
    .task {
      // Opening the screen asks for the substance, so it is loaded even without automatic loading
      await model.start(loadingIfNotCached: true)
    }
  }
}

private struct AnodyneSubstanceContent: View {
  let substance: AnodyneSubstance
  @State private var isShowingAddSheet = false
  @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
  private var customSubstances: FetchedResults<CustomSubstance>

  // The app's own substance of the same name, if there is one
  private var existingDestination: GlobalNavigationDestination? {
    let names = [substance.title] + substance.abbreviations
    for name in names {
      if let pwSubstance = SubstanceRepo.shared.getSubstance(name: name) {
        return .substance(substance: pwSubstance)
      }
      if let custom = customSubstances.first(where: { $0.nameUnwrapped.caseInsensitiveCompare(name) == .orderedSame }) {
        return .customSubstance(customSubstance: custom)
      }
    }
    return nil
  }

  var body: some View {
    List {
      Section {
        if let existingDestination {
          NavigationLink(value: existingDestination) {
            Label("Open in FreakLog", systemImage: "arrow.right.circle")
          }
        } else {
          Button {
            isShowingAddSheet = true
          } label: {
            Label("Add as Custom Substance", systemImage: "plus.circle")
          }
        }
      }
      namesSection
      if !substance.dosing.isEmpty {
        Section {
          ForEach(substance.dosing, id: \.method) { dosing in
            AnodyneDosingRow(dosing: dosing, isShowingAllTiers: true)
          }
        } header: {
          Text("Dosing")
        } footer: {
          Text(AnodyneDosingRow.disclaimer)
        }
      }
      if substance.durationOfAction != nil || substance.halfLife != nil {
        Section("Duration") {
          if let duration = substance.durationOfAction {
            LabeledText(label: "Duration of action", text: duration)
          }
          if let halfLife = substance.halfLife {
            LabeledText(label: "Biological half-life", text: halfLife)
          }
        }
      }
      ForEach(substance.effectGroups, id: \.name) { group in
        Section(group.name) {
          WrappingHStack(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(group.effects, id: \.self) { effect in
              Chip(name: effect)
            }
          }
        }
      }
      if !substance.reagents.isEmpty {
        Section {
          ForEach(substance.reagents, id: \.name) { reagent in
            HStack {
              Text(reagent.name)
              Spacer()
              ForEach(Array(reagent.colors.enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color(anodyneHex: hex))
                  .frame(width: 14, height: 14)
              }
            }
          }
        } header: {
          Text("Reagent Tests")
        } footer: {
          Text("Expected colors, changing over time from left to right.")
        }
      }
      pharmacologySection
      if !substance.scheduling.isEmpty {
        Section("Legal Status") {
          ForEach(substance.scheduling, id: \.self) { schedule in
            HStack {
              Text(schedule.country)
              Spacer()
              Text(schedule.schedule)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
          }
        }
      }
      reportsSection(title: "Erowid Experience Reports", reports: substance.erowidReports)
      reportsSection(title: "Reddit Experience Reports", reports: substance.redditReports)
      linksSection
    }
    .sheet(isPresented: $isShowingAddSheet) {
      AddAnodyneSubstanceSheet(substance: substance)
    }
  }

  @ViewBuilder
  private var namesSection: some View {
    let names = (substance.abbreviations + substance.slang + substance.aliases).uniqued()
    if !names.isEmpty || !substance.classes.isEmpty {
      Section("Names & Classes") {
        if !substance.classes.isEmpty {
          WrappingHStack(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(substance.classes, id: \.self) { substanceClass in
              Chip(name: substanceClass)
            }
          }
        }
        if !names.isEmpty {
          Text(names.prefix(30).joined(separator: ", "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var pharmacologySection: some View {
    if substance.hasPharmacologyTexts {
      Section("Pharmacology & Toxicity") {
        pharmacologyText("Interactions", substance.interactions)
        pharmacologyText("Reported fatal dose", substance.reportedFatalDose)
        pharmacologyText("Health effects", substance.healthEffects)
        pharmacologyText("Drug warnings", substance.drugWarnings)
        pharmacologyText("Treatment of overdose", substance.treatment)
        pharmacologyText("Mechanism of action", substance.mechanismOfAction)
        pharmacologyText("Metabolism", substance.metabolism)
      }
    }
  }

  @ViewBuilder
  private func pharmacologyText(_ title: String, _ text: String?) -> some View {
    if let text {
      DisclosureGroup(title) {
        Text(text)
          .font(.subheadline)
      }
    }
  }

  @ViewBuilder
  private func reportsSection(title: String, reports: [AnodyneSubstance.Link]) -> some View {
    if !reports.isEmpty {
      Section {
        ForEach(reports.prefix(15), id: \.url) { report in
          NavigationLink(report.title, value: GlobalNavigationDestination.webView(articleURL: report.url))
        }
      } header: {
        Text("\(title) (\(reports.count))")
      } footer: {
        if reports.count > 15 {
          Text("All \(reports.count) are listed on the AnodyneWiki page.")
        }
      }
    }
  }

  private var linksSection: some View {
    Section {
      NavigationLink(value: GlobalNavigationDestination.webView(articleURL: substance.pageURL)) {
        Label("AnodyneWiki Page", systemImage: "books.vertical")
      }
      ForEach(substance.references, id: \.url) { reference in
        NavigationLink(reference.title, value: GlobalNavigationDestination.webView(articleURL: reference.url))
      }
    } header: {
      Text("Links")
    } footer: {
      Text("From anodyne.wiki, an aggregating wiki. Its content is in the public domain unless noted otherwise.")
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
            AnodyneDosingRow(dosing: item.dosing, isShowingAllTiers: false)
          }
          if !categories.isEmpty {
            LabeledText(label: "Categories", text: categories.joined(separator: ", "))
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
