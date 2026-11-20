import SwiftUI

struct EditCustomRoaView: View {
  let substanceName: String
  let route: AdministrationRoute
  var customSubstance: CustomSubstance? = nil
  @Environment(\.managedObjectContext) private var context

  @State private var doseUnits = ""
  @State private var text: [CustomRoaField: String] = [:]
  @State private var existingRoa: CustomRoa?
  @State private var saveTask: Task<Void, Never>?

  // Current form state, which drives both the preview and what gets saved
  private var values: CustomRoaCodable {
    var values = CustomRoaCodable(administrationRoute: route, doseUnits: doseUnits)
    for (field, string) in text {
      values[field] = getDouble(from: string)
    }
    return values
  }

  var body: some View {
    let values = values
    Form {
      doseSection
      durationSection
      let roaDose = values.roaDose(fallbackUnits: customSubstance?.units)
      let roaDuration = values.roaDuration
      if roaDose != nil || roaDuration != nil {
        Section("Preview") {
          RoaPreview(substanceName: substanceName, route: route, roaDose: roaDose, roaDuration: roaDuration)
            .padding(.vertical, 4)
        }
      }
      if existingRoa != nil {
        Section {
          Button("Clear All Custom Data", role: .destructive) { clear() }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(route.rawValue.localizedCapitalized)
    .onAppear(perform: load)
    .onChange(of: doseUnits) { _ in saveDebounced() }
    .onChange(of: text) { _ in saveDebounced() }
  }

  // MARK: - Dose Section

  private var doseSection: some View {
    Section {
      HStack {
        Text("Units").foregroundStyle(.secondary)
        Spacer()
        TextField("e.g. mg, µg, mL", text: $doseUnits)
          .multilineTextAlignment(.trailing)
      }
      thresholdRow("Threshold", color: DoseRangeType.thresh.color, field: .lightDose)
      thresholdRow("Common", color: DoseRangeType.common.color, field: .commonDose)
      thresholdRow("Strong", color: DoseRangeType.strong.color, field: .strongDose)
      thresholdRow("Heavy", color: DoseRangeType.heavy.color, field: .heavyDose)
    } header: {
      Text("Dose")
    } footer: {
      Text("Each value is the minimum dose for that classification. Leave blank to skip.")
    }
  }

  private func thresholdRow(_ label: String, color: Color, field: CustomRoaField) -> some View {
    HStack(spacing: 10) {
      Circle().fill(color).frame(width: 10, height: 10)
      Text(label)
      Spacer()
      TextField("—", text: binding(for: field))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 90)
      if !doseUnits.isEmpty {
        Text(doseUnits)
          .foregroundStyle(.secondary)
          .frame(minWidth: 30, alignment: .leading)
      }
    }
  }

  // MARK: - Duration Section

  private var durationSection: some View {
    Section {
      durationRow("Onset", low: .onsetLow, high: .onsetHigh)
      durationRow("Come-up", low: .comeupLow, high: .comeupHigh)
      durationRow("Peak", low: .peakLow, high: .peakHigh)
      durationRow("Offset", low: .offsetLow, high: .offsetHigh)
      durationRow("Total", low: .totalLow, high: .totalHigh)
      durationRow("Afterglow", low: .afterglowLow, high: .afterglowHigh)
    } header: {
      Text("Duration")
    } footer: {
      Text("All times in minutes. Leave both blank to skip a phase.")
    }
  }

  private func durationRow(_ label: String, low: CustomRoaField, high: CustomRoaField) -> some View {
    HStack {
      Text(label).frame(minWidth: 70, alignment: .leading)
      Spacer()
      durationField("min", field: low)
      Text("–").foregroundStyle(.secondary)
      durationField("max", field: high)
      Text("min")
        .foregroundStyle(.secondary)
        .frame(width: 28, alignment: .leading)
    }
  }

  private func durationField(_ placeholder: String, field: CustomRoaField) -> some View {
    TextField(placeholder, text: binding(for: field))
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      .frame(width: 52)
      .padding(5)
      .background(Color(.secondarySystemGroupedBackground))
      .cornerRadius(6)
  }

  private func binding(for field: CustomRoaField) -> Binding<String> {
    Binding(get: { text[field] ?? "" }, set: { text[field] = $0 })
  }

  // MARK: - Data

  private func load() {
    existingRoa = PersistenceController.shared.getCustomRoa(for: substanceName, route: route)
    guard let existingRoa else {
      doseUnits = customSubstance?.unitsUnwrapped ?? ""
      return
    }
    let stored = existingRoa.values
    doseUnits = stored.doseUnits ?? ""
    for field in CustomRoaField.allCases {
      text[field] = stored[field]?.formatted() ?? ""
    }
  }

  private func clear() {
    saveTask?.cancel()
    deleteExisting()
    doseUnits = ""
    text = [:]
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
    let values = values
    guard !values.isEmpty else {
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
