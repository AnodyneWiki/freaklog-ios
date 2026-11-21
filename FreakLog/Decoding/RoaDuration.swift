import CoreData
import Foundation

struct RoaDuration: Codable, Hashable {
    let onset: DurationRange?
    let comeup: DurationRange?
    let peak: DurationRange?
    let offset: DurationRange?
    let total: DurationRange?
    let afterglow: DurationRange?

    // Onset, come-up, peak and offset, when all four have both bounds
    var fullPhases: (onset: FullDurationRange, comeup: FullDurationRange, peak: FullDurationRange, offset: FullDurationRange)? {
        guard let onset = onset?.maybeFullDurationRange,
              let comeup = comeup?.maybeFullDurationRange,
              let peak = peak?.maybeFullDurationRange,
              let offset = offset?.maybeFullDurationRange
        else { return nil }
        return (onset, comeup, peak, offset)
    }
}
