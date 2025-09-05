import CoreData
import Foundation

struct Tolerance: Decodable {
    let full: String?
    let half: String?
    let zero: String?
    let halfToleranceInHours: Double?
    let zeroToleranceInHours: Double?
}
