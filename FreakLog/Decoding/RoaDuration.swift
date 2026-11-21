import CoreData
import Foundation

struct RoaDuration: Codable, Equatable {
    let onset: DurationRange?
    let comeup: DurationRange?
    let peak: DurationRange?
    let offset: DurationRange?
    let total: DurationRange?
    let afterglow: DurationRange?
}
