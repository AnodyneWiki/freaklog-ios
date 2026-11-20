import Foundation

struct CustomRoaCodable: Codable {
  let administrationRoute: AdministrationRoute
  let doseUnits: String?
  let lightDose: Double?
  let commonDose: Double?
  let strongDose: Double?
  let heavyDose: Double?
  let onsetLow: Double?
  let onsetHigh: Double?
  let comeupLow: Double?
  let comeupHigh: Double?
  let peakLow: Double?
  let peakHigh: Double?
  let offsetLow: Double?
  let offsetHigh: Double?
  let totalLow: Double?
  let totalHigh: Double?
  let afterglowLow: Double?
  let afterglowHigh: Double?
}

extension CustomRoaCodable {
  init(roa: CustomRoa) {
    administrationRoute = roa.administrationRouteUnwrapped
    doseUnits = roa.doseUnits
    lightDose = roa.lightDose > 0 ? roa.lightDose : nil
    commonDose = roa.commonDose > 0 ? roa.commonDose : nil
    strongDose = roa.strongDose > 0 ? roa.strongDose : nil
    heavyDose = roa.heavyDose > 0 ? roa.heavyDose : nil
    onsetLow = roa.onsetLow > 0 ? roa.onsetLow : nil
    onsetHigh = roa.onsetHigh > 0 ? roa.onsetHigh : nil
    comeupLow = roa.comeupLow > 0 ? roa.comeupLow : nil
    comeupHigh = roa.comeupHigh > 0 ? roa.comeupHigh : nil
    peakLow = roa.peakLow > 0 ? roa.peakLow : nil
    peakHigh = roa.peakHigh > 0 ? roa.peakHigh : nil
    offsetLow = roa.offsetLow > 0 ? roa.offsetLow : nil
    offsetHigh = roa.offsetHigh > 0 ? roa.offsetHigh : nil
    totalLow = roa.totalLow > 0 ? roa.totalLow : nil
    totalHigh = roa.totalHigh > 0 ? roa.totalHigh : nil
    afterglowLow = roa.afterglowLow > 0 ? roa.afterglowLow : nil
    afterglowHigh = roa.afterglowHigh > 0 ? roa.afterglowHigh : nil
  }

  func apply(to roa: CustomRoa) {
    roa.administrationRoute = administrationRoute.rawValue
    roa.doseUnits = doseUnits
    roa.lightDose = lightDose ?? 0
    roa.commonDose = commonDose ?? 0
    roa.strongDose = strongDose ?? 0
    roa.heavyDose = heavyDose ?? 0
    roa.onsetLow = onsetLow ?? 0
    roa.onsetHigh = onsetHigh ?? 0
    roa.comeupLow = comeupLow ?? 0
    roa.comeupHigh = comeupHigh ?? 0
    roa.peakLow = peakLow ?? 0
    roa.peakHigh = peakHigh ?? 0
    roa.offsetLow = offsetLow ?? 0
    roa.offsetHigh = offsetHigh ?? 0
    roa.totalLow = totalLow ?? 0
    roa.totalHigh = totalHigh ?? 0
    roa.afterglowLow = afterglowLow ?? 0
    roa.afterglowHigh = afterglowHigh ?? 0
  }
}
