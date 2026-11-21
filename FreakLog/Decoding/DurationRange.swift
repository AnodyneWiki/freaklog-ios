import CoreData
import Foundation

struct DurationRange: Codable, Equatable {
    let min: Double?
    let max: Double?
    let units: Units

    enum Units: String, CaseIterable, Codable {
        case seconds, minutes, hours, days
    }

    var minSec: Double? {
        convertToSec(value: min)
    }

    var maxSec: Double? {
        convertToSec(value: max)
    }

    var displayString: String? {
        guard min != nil || max != nil else { return nil }
        var result: String
        if let min, min == max {
            result = min.formatted()
        } else {
            result = "\(min?.formatted() ?? "..")-\(max?.formatted() ?? "..")"
        }
        switch units {
        case .seconds:
            result += "s"
        case .minutes:
            result += "m"
        case .hours:
            result += "h"
        case .days:
            result += "d"
        }
        return result
    }

    private func convertToSec(value: Double?) -> Double? {
        guard var convert = value else { return nil }
        var unit: UnitDuration
        switch units {
        case .seconds:
            unit = UnitDuration.seconds
        case .minutes:
            unit = UnitDuration.minutes
        case .hours:
            unit = UnitDuration.hours
        case .days:
            convert *= 24
            unit = UnitDuration.hours
        }
        return Measurement(value: convert, unit: unit).converted(to: .seconds).value
    }

    var maybeFullDurationRange: FullDurationRange? {
        if let min = minSec, let max = maxSec {
            return FullDurationRange(min: min, max: max)
        } else {
            return nil
        }
    }
}

struct FullDurationRange {
    let min: TimeInterval
    let max: TimeInterval

    func interpolateLinearly(at weightBetween0And1: Double) -> TimeInterval {
        let diff = max - min
        return min + (diff * weightBetween0And1)
    }
}
