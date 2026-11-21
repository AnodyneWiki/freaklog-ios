import CoreData

// A named place with optional coordinates: a picked Location or an exported LocationCodable.
protocol LocationValue {
    var name: String { get }
    var latitude: Double? { get }
    var longitude: Double? { get }
}

extension ExperienceLocation {
    var nameUnwrapped: String {
        name ?? "Unknown"
    }

    var latitudeUnwrapped: Double? {
        if latitude == 0 {
            return nil
        } else {
            return latitude
        }
    }

    var longitudeUnwrapped: Double? {
        if longitude == 0 {
            return nil
        } else {
            return longitude
        }
    }

    var asLocation: Location {
        Location(name: nameUnwrapped, longitude: longitudeUnwrapped, latitude: latitudeUnwrapped)
    }

    static func make(from value: some LocationValue, in context: NSManagedObjectContext) -> ExperienceLocation {
        let location = ExperienceLocation(context: context)
        location.update(from: value)
        return location
    }

    func update(from value: some LocationValue) {
        name = value.name
        latitude = value.latitude ?? 0
        longitude = value.longitude ?? 0
    }
}
