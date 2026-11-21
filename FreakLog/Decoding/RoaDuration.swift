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

extension RoaDuration {
    // A phase with unreadable data is left out instead of failing the route, and so the whole substance
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func phase(_ key: CodingKeys) -> DurationRange? {
            (try? container.decodeIfPresent(DurationRange.self, forKey: key)) ?? nil
        }
        self.init(
            onset: phase(.onset),
            comeup: phase(.comeup),
            peak: phase(.peak),
            offset: phase(.offset),
            total: phase(.total),
            afterglow: phase(.afterglow)
        )
    }
}
