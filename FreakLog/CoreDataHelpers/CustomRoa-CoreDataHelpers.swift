import Foundation

extension CustomRoa {
  var administrationRouteUnwrapped: AdministrationRoute {
    AdministrationRoute(rawValue: administrationRoute ?? "") ?? .oral
  }

  var roaDose: RoaDose? {
    let hasAny = lightDose > 0 || commonDose > 0 || strongDose > 0 || heavyDose > 0
    guard hasAny else { return nil }
    // Fall back to the parent custom substance's units if doseUnits is blank.
    let resolvedUnits: String
    if let u = doseUnits, !u.isEmpty {
      resolvedUnits = u
    } else if let parentUnits = customSubstance?.unitsUnwrapped, !parentUnits.isEmpty {
      resolvedUnits = parentUnits
    } else {
      return nil
    }
    return RoaDose(
      units: resolvedUnits,
      lightMin: lightDose > 0 ? lightDose : nil,
      commonMin: commonDose > 0 ? commonDose : nil,
      strongMin: strongDose > 0 ? strongDose : nil,
      heavyMin: heavyDose > 0 ? heavyDose : nil
    )
  }

  var roaDuration: RoaDuration? {
    let hasAny = onsetLow > 0 || onsetHigh > 0
      || comeupLow > 0 || comeupHigh > 0
      || peakLow > 0 || peakHigh > 0
      || offsetLow > 0 || offsetHigh > 0
      || totalLow > 0 || totalHigh > 0
      || afterglowLow > 0 || afterglowHigh > 0
    guard hasAny else { return nil }
    return RoaDuration(
      onset: makeDurationRange(low: onsetLow, high: onsetHigh),
      comeup: makeDurationRange(low: comeupLow, high: comeupHigh),
      peak: makeDurationRange(low: peakLow, high: peakHigh),
      offset: makeDurationRange(low: offsetLow, high: offsetHigh),
      total: makeDurationRange(low: totalLow, high: totalHigh),
      afterglow: makeDurationRange(low: afterglowLow, high: afterglowHigh)
    )
  }

  private func makeDurationRange(low: Double, high: Double) -> DurationRange? {
    guard low > 0 || high > 0 else { return nil }
    return DurationRange(
      min: low > 0 ? low : nil,
      max: high > 0 ? high : nil,
      units: .minutes
    )
  }
}
