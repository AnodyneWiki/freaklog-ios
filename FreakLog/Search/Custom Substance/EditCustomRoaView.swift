import CoreData
import SwiftUI

struct EditCustomRoaView: View {
  let substanceName: String
  let route: AdministrationRoute
  var customSubstance: CustomSubstance? = nil
  @Environment(\.managedObjectContext) private var context
  @AppStorage(PersistenceController.anodyneInstanceURLKey) private var instanceURL = ""

  // Saved form state; durations are always in minutes here
  @State private var values: CustomRoaCodable
  // What is typed in each field, with durations in `durationUnit`
  @State private var text: [CustomRoaField: String] = [:]
  @State private var durationUnit = DurationInputUnit.minutes
  @State private var existingRoa: CustomRoa?
  @State private var isShowingSaveError = false
  @State private var saveTask: Task<Void, Never>?
  @State private var copySources: [CopySource] = []
  @State private var anodyneSources: [CopySource] = []
  @State private var pendingCopy: CopySource?

  init(substanceName: String, route: AdministrationRoute, customSubstance: CustomSubstance? = nil) {
    self.substanceName = substanceName
    self.route = route
    self.customSubstance = customSubstance
    _values = State(initialValue: CustomRoaCodable(administrationRoute: route))
  }

  private var fallbackUnits: String? {
    CustomRoa.fallbackUnits(substanceName: substanceName, route: route, customSubstance: customSubstance)
  }

  // What the form shows without the user's data, which the app uses then too: PsychonautWiki's dose and
  // duration (none for custom substances), with AnodyneWiki's filling in either when it was loaded before.
  // Matching it means no new override is needed.
  private var baseline: CustomRoaCodable {
    let (dose, duration, _) = baselineData
    return CustomRoaCodable(administrationRoute: route, dose: dose, duration: duration)
  }

  private var baselineData: (dose: RoaDose?, duration: RoaDuration?, sources: [String]) {
    let substance = customSubstance == nil ? SubstanceRepo.shared.getSubstance(name: substanceName) : nil
    let anodyne = AnodyneFallbackStore.shared
    let pwDose = substance?.getDose(for: route)
    let pwDuration = substance?.getDuration(for: route)
    let anodyneDose = pwDose == nil ? anodyne.dose(for: substanceName, route: route) : nil
    let anodyneDuration = pwDuration == nil ? anodyne.duration(for: substanceName, route: route) : nil
    var sources: [String] = []
    if pwDose != nil || pwDuration != nil {
      sources.append("PsychonautWiki")
    }
    if anodyneDose != nil || anodyneDuration != nil {
      sources.append("AnodyneWiki")
    }
    return (pwDose ?? anodyneDose, pwDuration ?? anodyneDuration, sources)
  }

  // E.g. "PsychonautWiki" or "PsychonautWiki and AnodyneWiki"
  private var baselineSourceName: String {
    baselineData.sources.joined(separator: " and ")
  }

  private var isShowingDefaultData: Bool {
    existingRoa == nil && !baseline.isEmpty
  }

  var body: some View {
    Form {
      let roaDose = values.roaDose(fallbackUnits: fallbackUnits)
      let roaDuration = values.roaDuration
      if roaDose != nil || roaDuration != nil {
        Section {
          RoaPreview(substanceName: substanceName, route: route, roaDose: roaDose, roaDuration: roaDuration)
            .padding(.vertical, 4)
        } header: {
          Text("Preview")
        } footer: {
          if isShowingDefaultData {
            Text("Showing the \(baselineSourceName) data. Any change is saved as your own data for this route.")
          }
        }
      }
      if !copySources.isEmpty || !anodyneSources.isEmpty {
        copySection
      }
      doseSection
      durationSection
      if existingRoa != nil {
        Section {
          if baseline.isEmpty {
            Button("Clear All Custom Data", role: .destructive) { clear() }
          } else {
            Button("Reset to \(baselineSourceName) Data", role: .destructive) { clear() }
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(route.rawValue.localizedCapitalized)
    .onAppear(perform: load)
    .task(id: instanceURL) {
      await loadAnodyneSources()
    }
    .onChange(of: values) { _ in saveDebounced() }
    .alert("Couldn't save route changes", isPresented: $isShowingSaveError) {
      Button("Retry") { save() }
      Button("OK", role: .cancel) {}
    }
    .confirmationDialog(
      "Replace the data of this route?",
      isPresented: Binding(get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } }),
      titleVisibility: .visible,
      presenting: pendingCopy
    ) { source in
      Button("Copy \(source.title)", role: .destructive) { copy(source) }
    } message: { source in
      if source.isDoseOnly {
        Text("The dose entered here is replaced with AnodyneWiki's \(source.route.rawValue) dose. Durations stay.")
      } else {
        Text("The dose and duration entered here are replaced with those of \(source.route.rawValue).")
      }
    }
  }

  // MARK: - Copy Section

  private var copySection: some View {
    Section {
      Menu {
        if !copySources.isEmpty {
          Section("Other Routes") {
            ForEach(copySources, content: copyButton)
          }
        }
        if !anodyneSources.isEmpty {
          Section("AnodyneWiki Doses") {
            ForEach(anodyneSources, content: copyButton)
          }
        }
      } label: {
        Label("Copy Data From…", systemImage: "doc.on.doc")
      }
    } footer: {
      Text(
        "Start from another route's dose and duration, or from AnodyneWiki's doses for a route, "
          + "then adjust them for this one."
      )
    }
  }

  // Asks first when it would replace something already entered
  private func copyButton(_ source: CopySource) -> some View {
    Button(source.title) {
      let isReplacingNothing = source.isDoseOnly
        ? CustomRoaField.doseFields.allSatisfy { values[$0] == nil }
        : values.isEmpty
      if isReplacingNothing {
        copy(source)
      } else {
        pendingCopy = source
      }
    }
  }

  // MARK: - Dose Section

  private var doseSection: some View {
    Section {
      HStack {
        Text("Units")
        Spacer()
        TextField(fallbackUnits ?? "e.g. mg, µg, mL", text: doseUnitsBinding)
          .multilineTextAlignment(.trailing)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }
      doseRow("Light", color: DoseRangeType.light.color, field: .lightDose)
      doseRow("Common", color: DoseRangeType.common.color, field: .commonDose)
      doseRow("Strong", color: DoseRangeType.strong.color, field: .strongDose)
      doseRow("Heavy", color: DoseRangeType.heavy.color, field: .heavyDose)
    } header: {
      Text("Dose")
    } footer: {
      Text(
        "Enter the dose where each range starts. Anything below light counts as threshold. Leave blank to skip. "
          + (fallbackUnits.map { "Without units, \($0) is used." } ?? "Units are needed for the dose to be used.")
      )
    }
  }

  private var doseUnitsBinding: Binding<String> {
    Binding(get: { values.doseUnits ?? "" }, set: { values.doseUnits = $0 })
  }

  private func doseRow(_ label: String, color: Color, field: CustomRoaField) -> some View {
    HStack(spacing: 10) {
      Circle().fill(color).frame(width: 10, height: 10)
      Text(label)
      Spacer()
      Text("from").foregroundStyle(.secondary)
      numberField("—", field: field)
      Text(values.doseUnits.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackUnits ?? "")
        .foregroundStyle(.secondary)
        .frame(minWidth: 30, alignment: .leading)
    }
  }

  // MARK: - Duration Section

  private var durationSection: some View {
    Section {
      Picker("Units", selection: durationUnitBinding) {
        ForEach(DurationInputUnit.allCases, id: \.self) { unit in
          Text(unit.title).tag(unit)
        }
      }
      .pickerStyle(.segmented)
      .listRowSeparator(.hidden)
      ForEach(DurationPhase.allCases, id: \.self, content: durationRow)
    } header: {
      Text("Duration")
    } footer: {
      Text(
        "Enter one value for a fixed time or two for a range. Leave a phase blank to skip it. "
          + "The timeline is complete with onset, come-up, peak and offset, and drawn dotted where phases are missing."
      )
    }
  }

  private var durationUnitBinding: Binding<DurationInputUnit> {
    Binding(get: { durationUnit }, set: { unit in
      durationUnit = unit
      fillText()
    })
  }

  private func durationRow(_ phase: DurationPhase) -> some View {
    HStack(spacing: 6) {
      VStack(alignment: .leading, spacing: 2) {
        Text(phase.title)
        Text(phase.explanation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      numberField("from", field: phase.low)
      Text("–").foregroundStyle(.secondary)
      numberField("to", field: phase.high)
      Text(durationUnit.symbol)
        .foregroundStyle(.secondary)
        .frame(width: 26, alignment: .leading)
    }
  }

  private func numberField(_ placeholder: String, field: CustomRoaField) -> some View {
    TextField(placeholder, text: binding(for: field))
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      .frame(width: 52)
      .padding(5)
      .background(Color(.tertiarySystemFill))
      .cornerRadius(6)
  }

  private func binding(for field: CustomRoaField) -> Binding<String> {
    Binding(get: { text[field] ?? "" }, set: { string in
      text[field] = string
      let factor = field.isDuration ? durationUnit.minutes : 1
      values[field] = getDouble(from: string).map { $0 * factor }
    })
  }

  // MARK: - Data

  private func load() {
    existingRoa = PersistenceController.shared.getCustomRoa(for: substanceName, route: route)
    values = existingRoa?.values ?? baseline
    durationUnit = DurationInputUnit.suggested(for: values)
    fillText()
    copySources = AdministrationRoute.allCases.filter { $0 != route }.compactMap { otherRoute in
      let customValues = PersistenceController.shared.getCustomRoa(for: substanceName, route: otherRoute)?.values
      let otherValues = customValues
        ?? CustomRoaCodable.psychonautWikiValues(for: customSubstance == nil ? substanceName : nil, route: otherRoute)
      guard !otherValues.isEmpty else { return nil }
      return CopySource(route: otherRoute, values: otherValues, origin: customValues != nil ? .userData : .psychonautWiki)
    }
  }

  // AnodyneWiki's doses per route, if they are cached or load automatically
  private func loadAnodyneSources() async {
    anodyneSources = []
    if pendingCopy?.isDoseOnly == true { pendingCopy = nil }
    let otherNames = customSubstance == nil ? SubstanceRepo.shared.getSubstance(name: substanceName)?.commonNames ?? [] : []
    let client = AnodyneClient.shared
    let request = await client.requestContext()
    var lookup = await client.cachedLookup(for: substanceName, using: request)
    if lookup == nil, AnodyneClient.isAutomaticLoadingEnabled {
      lookup = try? await client.lookup(substanceName, otherNames: otherNames, using: request)
    }
    guard case let .found(substance) = lookup,
          await client.isCurrent(request), !Task.isCancelled, request.baseURL == AnodyneSubstance.baseURL else { return }
    var seenRoutes = Set<AdministrationRoute>()
    anodyneSources = substance.dosing.compactMap { dosing in
      guard let dosingRoute = dosing.route, seenRoutes.insert(dosingRoute).inserted else { return nil }
      return CopySource(route: dosingRoute, values: dosing.doseValues(for: dosingRoute), origin: .anodyneWiki)
    }
  }

  // Takes over the other route's values as they are, or only AnodyneWiki's doses; saving happens as for any edit
  private func copy(_ source: CopySource) {
    var copied = source.values
    if source.isDoseOnly {
      copied = values
      copied.doseUnits = source.values.doseUnits
      for field in CustomRoaField.doseFields {
        copied[field] = source.values[field]
      }
    }
    copied.administrationRoute = route
    values = copied
    durationUnit = DurationInputUnit.suggested(for: values)
    fillText()
  }

  // Rebuilds the typed text from `values`, e.g. after loading or switching the duration unit.
  private func fillText() {
    for field in CustomRoaField.allCases {
      let factor = field.isDuration ? durationUnit.minutes : 1
      text[field] = values[field].map { ($0 / factor).formatted(.number.precision(.fractionLength(0 ... 2))) } ?? ""
    }
  }

  private func clear() {
    saveTask?.cancel()
    do {
      try deleteExisting()
      values = baseline
      fillText()
    } catch {
      isShowingSaveError = true
    }
  }

  private func deleteExisting() throws {
    guard let existingRoa else { return }
    let edit = try PersistenceController.shared.journalEditContext()
    edit.delete(try PersistenceController.journalObject(existingRoa, in: edit))
    try edit.save()
    self.existingRoa = nil
  }

  private func saveDebounced() {
    saveTask?.cancel()
    saveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 400_000_000)
      guard !Task.isCancelled else { return }
      save()
    }
  }

  private func save() {
    let psychonautWiki = CustomRoaCodable.psychonautWikiValues(
      for: customSubstance == nil ? substanceName : nil,
      route: route
    )
    do {
      guard values.needsSavedRow(hasExistingRow: existingRoa != nil, baseline: baseline, psychonautWiki: psychonautWiki)
      else {
        try deleteExisting()
        return
      }
      let edit = try PersistenceController.shared.journalEditContext()
      let target = try existingRoa.map { try PersistenceController.journalObject($0, in: edit) }
        ?? CustomRoa(context: edit)
      target.substanceName = substanceName
      target.customSubstance = try customSubstance.map { try PersistenceController.journalObject($0, in: edit) }
      values.apply(to: target)
      try edit.save()
      existingRoa = context.object(with: target.objectID) as? CustomRoa
    } catch {
      isShowingSaveError = true
    }
  }
}

// A route's dose and duration to copy into the edited route: the user's data or PsychonautWiki's, or
// AnodyneWiki's doses (it has no durations to copy)
private struct CopySource: Identifiable {
  enum Origin {
    case userData, psychonautWiki, anodyneWiki
  }

  let route: AdministrationRoute
  let values: CustomRoaCodable
  let origin: Origin

  var id: String { "\(route.rawValue)-\(origin)" }

  var isDoseOnly: Bool { origin == .anodyneWiki }

  var title: String {
    let source = switch origin {
    case .userData: "your data"
    case .psychonautWiki: "PsychonautWiki"
    case .anodyneWiki: "AnodyneWiki"
    }
    return "\(route.rawValue.localizedCapitalized) (\(source))"
  }
}

private enum DurationInputUnit: CaseIterable {
  case minutes, hours

  var title: String {
    switch self {
    case .minutes: "Minutes"
    case .hours: "Hours"
    }
  }

  var symbol: String {
    switch self {
    case .minutes: "min"
    case .hours: "h"
    }
  }

  var minutes: Double {
    switch self {
    case .minutes: 1
    case .hours: 60
    }
  }

  // Hours read better once the total runs to several hours.
  static func suggested(for values: CustomRoaCodable) -> DurationInputUnit {
    let longest = CustomRoaField.allCases.filter(\.isDuration).compactMap { values[$0] }.max() ?? 0
    return longest >= 180 ? .hours : .minutes
  }
}
