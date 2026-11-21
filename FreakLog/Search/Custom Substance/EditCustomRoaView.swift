import SwiftUI

struct EditCustomRoaView: View {
  let substanceName: String
  let route: AdministrationRoute
  var customSubstance: CustomSubstance? = nil
  @Environment(\.managedObjectContext) private var context

  // Saved form state; durations are always in minutes here
  @State private var values: CustomRoaCodable
  // What is typed in each field, with durations in `durationUnit`
  @State private var text: [CustomRoaField: String] = [:]
  @State private var durationUnit = DurationInputUnit.minutes
  @State private var existingRoa: CustomRoa?
  @State private var saveTask: Task<Void, Never>?

  init(substanceName: String, route: AdministrationRoute, customSubstance: CustomSubstance? = nil) {
    self.substanceName = substanceName
    self.route = route
    self.customSubstance = customSubstance
    _values = State(initialValue: CustomRoaCodable(administrationRoute: route))
  }

  private var fallbackUnits: String? {
    CustomRoa.fallbackUnits(substanceName: substanceName, route: route, customSubstance: customSubstance)
  }

  // What the form shows without custom data: the PsychonautWiki data, if any. Matching it means no override is needed.
  private var baseline: CustomRoaCodable {
    CustomRoaCodable.psychonautWikiValues(for: customSubstance == nil ? substanceName : nil, route: route)
  }

  private var isShowingPsychonautWikiData: Bool {
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
          if isShowingPsychonautWikiData {
            Text("Showing the PsychonautWiki data. Any change is saved as your own data for this route.")
          }
        }
      }
      doseSection
      durationSection
      if existingRoa != nil {
        Section {
          if baseline.isEmpty {
            Button("Clear All Custom Data", role: .destructive) { clear() }
          } else {
            Button("Reset to PsychonautWiki Data", role: .destructive) { clear() }
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(route.rawValue.localizedCapitalized)
    .onAppear(perform: load)
    .onChange(of: values) { _ in saveDebounced() }
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
    deleteExisting()
    values = baseline
    fillText()
  }

  private func deleteExisting() {
    guard let existingRoa else { return }
    context.delete(existingRoa)
    try? context.save()
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
    guard !values.isEmpty, values != baseline else {
      deleteExisting()
      return
    }
    let target = existingRoa ?? CustomRoa(context: context)
    target.substanceName = substanceName
    target.customSubstance = customSubstance
    values.apply(to: target)
    try? context.save()
    existingRoa = target
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
