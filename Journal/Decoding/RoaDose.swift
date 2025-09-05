import CoreData
import Foundation

struct RoaDose: Decodable {
    let units: String
    let lightMin: Double?
    let commonMin: Double?
    let strongMin: Double?
    let heavyMin: Double?

    var shouldUseVolumetricDosing: Bool {
        if units == "µg" {
            return true
        } else if units == "mg" {
            if let commonMin, commonMin < 10 {
                return true
            }
            if let strongMin, strongMin < 15 {
                return true
            }
            if let heavyMin, heavyMin < 20 {
                return true
            }
        }
        return false
    }

    func getRangeType(for dose: Double, with doseUnits: String) -> DoseRangeType {
        guard units == doseUnits else { return .none }
        if let lightMinUnwrap = lightMin,
           dose < lightMinUnwrap {
            return .thresh
        } else if let lightMinUnwrap = lightMin,
                  let commonMinUnwrap = commonMin,
                  lightMinUnwrap <= dose && dose < commonMinUnwrap {
            return .light
        } else if let commonMinUnwrap = commonMin,
                  let strongMinUnwrap = strongMin,
                  commonMinUnwrap <= dose && dose < strongMinUnwrap {
            return .common
        } else if let strongMinUnwrap = strongMin,
                  let heavyMinUnwrap = heavyMin,
                  strongMinUnwrap <= dose && dose < heavyMinUnwrap {
            return .strong
        } else if let heavyMinUnwrap = heavyMin,
                  heavyMinUnwrap <= dose {
            return .heavy
        } else {
            return .none
        }
    }

    func getNumDots(ingestionDose: Double?, ingestionUnits: String?) -> Int? {
        guard let dose = ingestionDose else { return nil }
        guard ingestionUnits == units else { return nil }
        if let lightMinUnwrap = lightMin,
           dose < lightMinUnwrap {
            return 0
        } else if let lightMinUnwrap = lightMin,
                  let commonMinUnwrap = commonMin,
                  lightMinUnwrap <= dose && dose < commonMinUnwrap {
            return 1
        } else if let commonMinUnwrap = commonMin,
                  let strongMinUnwrap = strongMin,
                  commonMinUnwrap <= dose && dose < strongMinUnwrap {
            return 2
        } else if let strongMinUnwrap = strongMin,
                  let heavyMinUnwrap = heavyMin,
                  strongMinUnwrap <= dose && dose < heavyMinUnwrap {
            return 3
        } else if let heavyMinUnwrap = heavyMin {
            if heavyMinUnwrap <= dose {
                let timesHeavy = Int(floor(dose / heavyMinUnwrap))
                var rest = dose.remainder(dividingBy: heavyMinUnwrap)
                if rest < 0 {
                    rest += heavyMinUnwrap
                }
                return (timesHeavy * 4) + getNumDotsUpTo4(dose: rest)
            } else {
                return Int(floor(dose / heavyMinUnwrap))
            }
        } else {
            return nil
        }
    }

    private func getNumDotsUpTo4(dose: Double) -> Int {
        if let lightMinUnwrap = lightMin,
           dose < lightMinUnwrap {
            return 0
        } else if let lightMinUnwrap = lightMin,
                  let commonMinUnwrap = commonMin,
                  lightMinUnwrap <= dose && dose < commonMinUnwrap {
            return 1
        } else if let commonMinUnwrap = commonMin,
                  let strongMinUnwrap = strongMin,
                  commonMinUnwrap <= dose && dose < strongMinUnwrap {
            return 2
        } else if let strongMinUnwrap = strongMin,
                  let heavyMinUnwrap = heavyMin,
                  strongMinUnwrap <= dose && dose < heavyMinUnwrap {
            return 3
        } else if let heavyMinUnwrap = heavyMin {
            return Int(floor(dose / heavyMinUnwrap))
        } else {
            return 0
        }
    }

    var averageCommonDose: Double? {
        if let commonMinUnwrap = commonMin,
           let commonMaxUnwrap = strongMin {
            return (commonMinUnwrap + commonMaxUnwrap) / 2
        } else {
            return nil
        }
    }

    func getStrengthRelativeToCommonDose(dose: Double) -> Double? {
        if let avg = averageCommonDose, avg > 0 {
            return dose/avg
        } else {
            return nil
        }
    }
}
