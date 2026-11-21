import Foundation

struct LocationCodable: Codable, LocationValue {
    let name: String
    let latitude: Double?
    let longitude: Double?
}

extension LocationCodable {
    init(_ location: ExperienceLocation) {
        self.init(name: location.nameUnwrapped, latitude: location.latitudeUnwrapped, longitude: location.longitudeUnwrapped)
    }
}
