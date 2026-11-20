import SwiftUI

struct EditCustomRoaView: View {
  let substanceName: String
  let route: AdministrationRoute
  var customSubstance: CustomSubstance? = nil
  @Environment(\.managedObjectContext) private var context

  @State private var doseUnits = ""
  @State private var lightDose = ""
  @State private var commonDose = ""
  @State private var strongDose = ""
  @State private var heavyDose = ""
  @State private var onsetLow = ""
  @State private var onsetHigh = ""
  @State private var comeupLow = ""
  @State private var comeupHigh = ""
  @State private var peakLow = ""
  @State private var peakHigh = ""
  @State private var offsetLow = ""
  @State private var offsetHigh = ""
  @State private var totalLow = ""
  @State private var totalHigh = ""
  @State private var afterglowLow = ""
  @State private var afterglowHigh = ""

  @State private var selectedTime = Date()
  @State private var timelineModel: TimelineModel?
  @State private var saveTask: Task<Void, Never>?

  private var existingRoa: CustomRoa? {
    if let customSubstance {
      return customSubstance.getRoa(for: route)
    }
    return PersistenceController.shared.getCustomRoa(for: substanceName, route: route)
  }

  // MARK: - Computed preview from current form state (no CoreData needed)

  private var liveRoaDose: RoaDose? {
    let hasAny = [lightDose, commonDose, strongDose, heavyDose].contains { !$0.isEmpty }
    guard hasAny, !doseUnits.isEmpty else { return nil }
    return RoaDose(
      units: doseUnits,
      lightMin: parseOpt(lightDose),
      commonMin: parseOpt(commonDose),
      strongMin: parseOpt(strongDose),
      heavyMin: parseOpt(heavyDose)
    )
  }

  private var liveRoaDuration: RoaDuration? {
    let vals = [onsetLow, onsetHigh, comeupLow, comeupHigh, peakLow, peakHigh,
                offsetLow, offsetHigh, totalLow, totalHigh, afterglowLow, afterglowHigh]
    guard vals.contains(where: { !$0.isEmpty }) else { return nil }
    return RoaDuration(
      onset: liveDur(onsetLow, onsetHigh),
      comeup: liveDur(comeupLow, comeupHigh),
      peak: liveDur(peakLow, peakHigh),
      offset: liveDur(offsetLow, offsetHigh),
      total: liveDur(totalLow, totalHigh),
      afterglow: liveDur(afterglowLow, afterglowHigh)
    )
  }

  private func liveDur(_ low: String, _ high: String) -> DurationRange? {
    let lo = parseOpt(low), hi = parseOpt(high)
    guard lo != nil || hi != nil else { return nil }
    return DurationRange(min: lo, max: hi, units: .minutes)
  }

  // MARK: - Body

  var body: some View {
    Form {
      doseSection
      durationSection
      previewSection
      if existingRoa != nil {
        Section {
          Button("Clear All Custom Data", role: .destructive) { clearRoa() }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(route.rawValue.localizedCapitalized)
    .onAppear { loadFromRoa(); updateTimeline() }
    .onChange(of: selectedTime) { _ in updateTimeline() }
    .onChange(of: doseUnits) { _ in saveDebounced() }
    .onChange(of: lightDose) { _ in saveDebounced() }
    .onChange(of: commonDose) { _ in saveDebounced() }
    .onChange(of: strongDose) { _ in saveDebounced() }
    .onChange(of: heavyDose) { _ in saveDebounced() }
    .onChange(of: onsetLow) { _ in saveDebounced() }
    .onChange(of: onsetHigh) { _ in saveDebounced() }
    .onChange(of: comeupLow) { _ in saveDebounced() }
    .onChange(of: comeupHigh) { _ in saveDebounced() }
    .onChange(of: peakLow) { _ in saveDebounced() }
    .onChange(of: peakHigh) { _ in saveDebounced() }
    .onChange(of: offsetLow) { _ in saveDebounced() }
    .onChange(of: offsetHigh) { _ in saveDebounced() }
    .onChange(of: totalLow) { _ in saveDebounced() }
    .onChange(of: totalHigh) { _ in saveDebounced() }
    .onChange(of: afterglowLow) { _ in saveDebounced() }
    .onChange(of: afterglowHigh) { _ in saveDebounced() }
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
      thresholdRow("Threshold", color: DoseRangeType.thresh.color, value: $lightDose)
      thresholdRow("Common", color: DoseRangeType.common.color, value: $commonDose)
      thresholdRow("Strong", color: DoseRangeType.strong.color, value: $strongDose)
      thresholdRow("Heavy", color: DoseRangeType.heavy.color, value: $heavyDose)
    } header: {
      Text("Dose")
    } footer: {
      Text("Each value is the minimum dose for that classification. Leave blank to skip.")
    }
  }

  private func thresholdRow(_ label: String, color: Color, value: Binding<String>) -> some View {
    HStack(spacing: 10) {
      Circle().fill(color).frame(width: 10, height: 10)
      Text(label)
      Spacer()
      TextField("—", text: value)
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
      durationRow("Onset", low: $onsetLow, high: $onsetHigh)
      durationRow("Come-up", low: $comeupLow, high: $comeupHigh)
      durationRow("Peak", low: $peakLow, high: $peakHigh)
      durationRow("Offset", low: $offsetLow, high: $offsetHigh)
      durationRow("Total", low: $totalLow, high: $totalHigh)
      durationRow("Afterglow", low: $afterglowLow, high: $afterglowHigh)
    } header: {
      Text("Duration")
    } footer: {
      Text("All times in minutes. Leave both blank to skip a phase.")
    }
  }

  private func durationRow(_ label: String, low: Binding<String>, high: Binding<String>) -> some View {
    HStack {
      Text(label).frame(minWidth: 70, alignment: .leading)
      Spacer()
      TextField("min", text: low)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 52)
        .padding(5)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(6)
      Text("–").foregroundStyle(.secondary)
      TextField("max", text: high)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 52)
        .padding(5)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(6)
      Text("min")
        .foregroundStyle(.secondary)
        .frame(width: 28, alignment: .leading)
    }
  }

  // MARK: - Preview Section (bottom, only when data is entered)

  @ViewBuilder
  private var previewSection: some View {
    let hasDose = liveRoaDose != nil
    let hasDuration = liveRoaDuration != nil
    if hasDose || hasDuration {
      Section("Preview") {
        VStack(alignment: .leading, spacing: 12) {
          if let roaDose = liveRoaDose {
            RoaDoseRow(roaDose: roaDose)
          }
          if let roaDuration = liveRoaDuration {
            OneRoaDurationRow(duration: roaDuration, color: route.color)
          }
          if let model = timelineModel, model.isWorthDrawing {
            Divider()
            HStack {
              DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
              Spacer()
              Button("Now") { selectedTime = .now }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            EffectTimeline(timelineModel: model, timeDisplayStyle: .relativeToNow)
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  // MARK: - Data

  private func loadFromRoa() {
    guard let roa = existingRoa else {
      if let cs = customSubstance, !cs.unitsUnwrapped.isEmpty {
        doseUnits = cs.unitsUnwrapped
      }
      return
    }
    doseUnits = roa.doseUnits ?? ""
    lightDose = fmt(roa.lightDose); commonDose = fmt(roa.commonDose)
    strongDose = fmt(roa.strongDose); heavyDose = fmt(roa.heavyDose)
    onsetLow = fmt(roa.onsetLow); onsetHigh = fmt(roa.onsetHigh)
    comeupLow = fmt(roa.comeupLow); comeupHigh = fmt(roa.comeupHigh)
    peakLow = fmt(roa.peakLow); peakHigh = fmt(roa.peakHigh)
    offsetLow = fmt(roa.offsetLow); offsetHigh = fmt(roa.offsetHigh)
    totalLow = fmt(roa.totalLow); totalHigh = fmt(roa.totalHigh)
    afterglowLow = fmt(roa.afterglowLow); afterglowHigh = fmt(roa.afterglowHigh)
  }

  private func fmt(_ v: Double) -> String { v > 0 ? v.formatted() : "" }

  private func clearRoa() {
    if let roa = existingRoa { context.delete(roa); try? context.save() }
    doseUnits = ""
    lightDose = ""; commonDose = ""; strongDose = ""; heavyDose = ""
    onsetLow = ""; onsetHigh = ""; comeupLow = ""; comeupHigh = ""
    peakLow = ""; peakHigh = ""; offsetLow = ""; offsetHigh = ""
    totalLow = ""; totalHigh = ""; afterglowLow = ""; afterglowHigh = ""
    timelineModel = nil
  }

  private func saveDebounced() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(nanoseconds: 400_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run { save() }
    }
  }

  private func save() {
    let allFields = [lightDose, commonDose, strongDose, heavyDose, onsetLow, onsetHigh,
                     comeupLow, comeupHigh, peakLow, peakHigh, offsetLow, offsetHigh,
                     totalLow, totalHigh, afterglowLow, afterglowHigh]
    let isEmpty = allFields.allSatisfy { $0.isEmpty } && doseUnits.isEmpty
    if isEmpty {
      if let roa = existingRoa { context.delete(roa); try? context.save() }
      return
    }
    let target: CustomRoa
    if let existing = existingRoa {
      target = existing
    } else {
      let newRoa = CustomRoa(context: context)
      newRoa.administrationRoute = route.rawValue
      newRoa.substanceName = substanceName
      newRoa.customSubstance = customSubstance
      target = newRoa
    }
    target.doseUnits = doseUnits.isEmpty ? nil : doseUnits
    target.lightDose = parse(lightDose); target.commonDose = parse(commonDose)
    target.strongDose = parse(strongDose); target.heavyDose = parse(heavyDose)
    target.onsetLow = parse(onsetLow); target.onsetHigh = parse(onsetHigh)
    target.comeupLow = parse(comeupLow); target.comeupHigh = parse(comeupHigh)
    target.peakLow = parse(peakLow); target.peakHigh = parse(peakHigh)
    target.offsetLow = parse(offsetLow); target.offsetHigh = parse(offsetHigh)
    target.totalLow = parse(totalLow); target.totalHigh = parse(totalHigh)
    target.afterglowLow = parse(afterglowLow); target.afterglowHigh = parse(afterglowHigh)
    try? context.save()
    updateTimeline()
  }

  private func updateTimeline() {
    guard liveRoaDuration != nil else { timelineModel = nil; return }
    timelineModel = TimelineModel(
      substanceGroups: [SubstanceIngestionGroup(
        substanceName: substanceName,
        color: route.color,
        routeMinInfos: [RouteMinInfo(
          route: route,
          ingestions: [IngestionMinInfo(dose: nil, time: selectedTime, endTime: nil, onsetDelayInHours: 0)]
        )]
      )],
      everythingForEachRating: [],
      everythingForEachTimedNote: [],
      areRedosesDrawnIndividually: true,
      areSubstanceHeightsIndependent: false
    )
  }

  private func parse(_ t: String) -> Double {
    Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private func parseOpt(_ t: String) -> Double? {
    let v = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
    return v > 0 ? v : nil
  }
}
