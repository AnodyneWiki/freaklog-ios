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
        return range(of: dose)
    }

    // The range the dose falls in. A range needs both of its bounds, except for thresh and heavy.
    private func range(of dose: Double) -> DoseRangeType {
        if let lightMin, dose < lightMin {
            return .thresh
        } else if let lightMin, let commonMin, lightMin <= dose && dose < commonMin {
            return .light
        } else if let commonMin, let strongMin, commonMin <= dose && dose < strongMin {
            return .common
        } else if let strongMin, let heavyMin, strongMin <= dose && dose < heavyMin {
            return .strong
        } else if let heavyMin, heavyMin <= dose {
            return .heavy
        } else {
            return .none
        }
    }

    // Dots for doses below heavy: thresh 0, light 1, common 2, strong 3
    private func dotsBelowHeavy(for dose: Double) -> Int? {
        switch range(of: dose) {
        case .thresh: 0
        case .light: 1
        case .common: 2
        case .strong: 3
        case .heavy, .none: nil
        }
    }

    // Each multiple of the heavy dose adds 4 dots, plus the dots for the rest
    func getNumDots(ingestionDose: Double?, ingestionUnits: String?) -> Int? {
        guard let dose = ingestionDose else { return nil }
        guard ingestionUnits == units else { return nil }
        if let dots = dotsBelowHeavy(for: dose) {
            return dots
        }
        guard let heavyMin else { return nil }
        guard heavyMin <= dose else { return Int(floor(dose / heavyMin)) }
        let timesHeavy = Int(floor(dose / heavyMin))
        var rest = dose.remainder(dividingBy: heavyMin)
        if rest < 0 {
            rest += heavyMin
        }
        return (timesHeavy * 4) + getNumDotsUpTo4(dose: rest)
    }

    private func getNumDotsUpTo4(dose: Double) -> Int {
        dotsBelowHeavy(for: dose) ?? heavyMin.map { Int(floor(dose / $0)) } ?? 0
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
