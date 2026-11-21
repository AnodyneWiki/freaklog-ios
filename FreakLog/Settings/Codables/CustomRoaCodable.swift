import Foundation

// Value form of a CustomRoa. Used for export/import and as the editing model.
// Unset values are nil here and 0 on the CoreData entity.
struct CustomRoaCodable: Codable, Equatable {
  var administrationRoute: AdministrationRoute
  var doseUnits: String?
  var lightDose: Double?
  var commonDose: Double?
  var strongDose: Double?
  var heavyDose: Double?
  var onsetLow: Double?
  var onsetHigh: Double?
  var comeupLow: Double?
  var comeupHigh: Double?
  var peakLow: Double?
  var peakHigh: Double?
  var offsetLow: Double?
  var offsetHigh: Double?
  var totalLow: Double?
  var totalHigh: Double?
  var afterglowLow: Double?
  var afterglowHigh: Double?

  init(administrationRoute: AdministrationRoute, doseUnits: String? = nil) {
    self.administrationRoute = administrationRoute
    self.doseUnits = doseUnits
  }

  // Prefills the form from existing data (e.g. PsychonautWiki). Durations are converted to minutes.
  init(administrationRoute: AdministrationRoute, dose: RoaDose?, duration: RoaDuration?) {
    self.init(administrationRoute: administrationRoute, doseUnits: dose?.units)
    self[.lightDose] = dose?.lightMin
    self[.commonDose] = dose?.commonMin
    self[.strongDose] = dose?.strongMin
    self[.heavyDose] = dose?.heavyMin
    for phase in DurationPhase.allCases {
      let range = duration.flatMap(phase.range(in:))
      self[phase.low] = range?.minSec.map { $0 / 60 }
      self[phase.high] = range?.maxSec.map { $0 / 60 }
    }
  }

  // The PsychonautWiki data for a route as form values, empty when there is none (e.g. for custom substances)
  static func psychonautWikiValues(for substanceName: String?, route: AdministrationRoute) -> CustomRoaCodable {
    let substance = substanceName.flatMap { SubstanceRepo.shared.getSubstance(name: $0) }
    return CustomRoaCodable(
      administrationRoute: route,
      dose: substance?.getDose(for: route),
      duration: substance?.getDuration(for: route)
    )
  }

  init(roa: CustomRoa) {
    self.init(administrationRoute: roa.administrationRouteUnwrapped, doseUnits: roa.doseUnits)
    for field in CustomRoaField.allCases {
      self[field] = roa[keyPath: field.roaKeyPath]
    }
  }

  subscript(field: CustomRoaField) -> Double? {
    get { self[keyPath: field.keyPath] }
    set { self[keyPath: field.keyPath] = newValue.flatMap { $0 > 0 ? $0 : nil } }
  }

  var isEmpty: Bool {
    CustomRoaField.allCases.allSatisfy { self[$0] == nil }
  }

  func apply(to roa: CustomRoa) {
    roa.administrationRoute = administrationRoute.rawValue
    roa.doseUnits = doseUnits?.isEmpty == false ? doseUnits : nil
    for field in CustomRoaField.allCases {
      roa[keyPath: field.roaKeyPath] = self[field] ?? 0
    }
  }

  func roaDose(fallbackUnits: String?) -> RoaDose? {
    guard lightDose != nil || commonDose != nil || strongDose != nil || heavyDose != nil else { return nil }
    guard let units = [doseUnits, fallbackUnits].compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
    return RoaDose(units: units, lightMin: lightDose, commonMin: commonDose, strongMin: strongDose, heavyMin: heavyDose)
  }

  var roaDuration: RoaDuration? {
    let duration = RoaDuration(
      onset: range(of: .onset),
      comeup: range(of: .comeup),
      peak: range(of: .peak),
      offset: range(of: .offset),
      total: range(of: .total),
      afterglow: range(of: .afterglow)
    )
    return DurationPhase.allCases.allSatisfy { $0.range(in: duration) == nil } ? nil : duration
  }

  // A single value is a fixed time rather than a half-open range, so the timeline can still draw the phase.
  private func range(of phase: DurationPhase) -> DurationRange? {
    let bounds = [self[phase.low], self[phase.high]].compactMap { $0 }
    guard let min = bounds.min(), let max = bounds.max() else { return nil }
    return DurationRange(min: min, max: max, units: .minutes)
  }
}

enum DurationPhase: CaseIterable {
  case onset, comeup, peak, offset, total, afterglow

  var title: String {
    switch self {
    case .onset: "Onset"
    case .comeup: "Come-up"
    case .peak: "Peak"
    case .offset: "Offset"
    case .total: "Total"
    case .afterglow: "Afterglow"
    }
  }

  var explanation: String {
    switch self {
    case .onset: "Until the first effects"
    case .comeup: "From first effects to the peak"
    case .peak: "How long the peak lasts"
    case .offset: "From the peak back to baseline"
    case .total: "From ingestion to baseline"
    case .afterglow: "Lingering after-effects"
    }
  }

  var low: CustomRoaField {
    switch self {
    case .onset: .onsetLow
    case .comeup: .comeupLow
    case .peak: .peakLow
    case .offset: .offsetLow
    case .total: .totalLow
    case .afterglow: .afterglowLow
    }
  }

  var high: CustomRoaField {
    switch self {
    case .onset: .onsetHigh
    case .comeup: .comeupHigh
    case .peak: .peakHigh
    case .offset: .offsetHigh
    case .total: .totalHigh
    case .afterglow: .afterglowHigh
    }
  }

  func range(in duration: RoaDuration) -> DurationRange? {
    switch self {
    case .onset: duration.onset
    case .comeup: duration.comeup
    case .peak: duration.peak
    case .offset: duration.offset
    case .total: duration.total
    case .afterglow: duration.afterglow
    }
  }
}

enum CustomRoaField: CaseIterable {
  case lightDose, commonDose, strongDose, heavyDose
  case onsetLow, onsetHigh, comeupLow, comeupHigh, peakLow, peakHigh
  case offsetLow, offsetHigh, totalLow, totalHigh, afterglowLow, afterglowHigh

  static let doseFields: [CustomRoaField] = [.lightDose, .commonDose, .strongDose, .heavyDose]

  var isDuration: Bool {
    !Self.doseFields.contains(self)
  }

  var keyPath: WritableKeyPath<CustomRoaCodable, Double?> {
    switch self {
    case .lightDose: \.lightDose
    case .commonDose: \.commonDose
    case .strongDose: \.strongDose
    case .heavyDose: \.heavyDose
    case .onsetLow: \.onsetLow
    case .onsetHigh: \.onsetHigh
    case .comeupLow: \.comeupLow
    case .comeupHigh: \.comeupHigh
    case .peakLow: \.peakLow
    case .peakHigh: \.peakHigh
    case .offsetLow: \.offsetLow
    case .offsetHigh: \.offsetHigh
    case .totalLow: \.totalLow
    case .totalHigh: \.totalHigh
    case .afterglowLow: \.afterglowLow
    case .afterglowHigh: \.afterglowHigh
    }
  }

  var roaKeyPath: ReferenceWritableKeyPath<CustomRoa, Double> {
    switch self {
    case .lightDose: \.lightDose
    case .commonDose: \.commonDose
    case .strongDose: \.strongDose
    case .heavyDose: \.heavyDose
    case .onsetLow: \.onsetLow
    case .onsetHigh: \.onsetHigh
    case .comeupLow: \.comeupLow
    case .comeupHigh: \.comeupHigh
    case .peakLow: \.peakLow
    case .peakHigh: \.peakHigh
    case .offsetLow: \.offsetLow
    case .offsetHigh: \.offsetHigh
    case .totalLow: \.totalLow
    case .totalHigh: \.totalHigh
    case .afterglowLow: \.afterglowLow
    case .afterglowHigh: \.afterglowHigh
    }
  }
}
