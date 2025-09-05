import CoreData
import Foundation

struct Roa: Decodable {
    let name: AdministrationRoute
    let dose: RoaDose?
    let duration: RoaDuration?
    let bioavailability: RoaRange?
}
