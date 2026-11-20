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
      onset: Self.range(onsetLow, onsetHigh),
      comeup: Self.range(comeupLow, comeupHigh),
      peak: Self.range(peakLow, peakHigh),
      offset: Self.range(offsetLow, offsetHigh),
      total: Self.range(totalLow, totalHigh),
      afterglow: Self.range(afterglowLow, afterglowHigh)
    )
    let ranges = [duration.onset, duration.comeup, duration.peak, duration.offset, duration.total, duration.afterglow]
    return ranges.allSatisfy { $0 == nil } ? nil : duration
  }

  private static func range(_ low: Double?, _ high: Double?) -> DurationRange? {
    guard low != nil || high != nil else { return nil }
    return DurationRange(min: low, max: high, units: .minutes)
  }
}

enum CustomRoaField: CaseIterable {
  case lightDose, commonDose, strongDose, heavyDose
  case onsetLow, onsetHigh, comeupLow, comeupHigh, peakLow, peakHigh
  case offsetLow, offsetHigh, totalLow, totalHigh, afterglowLow, afterglowHigh

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
