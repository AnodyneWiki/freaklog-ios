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
        // Older stores used zero as the sentinel for an absent coordinate.
        hasExplicitLatitude || latitude != 0 ? latitude : nil
    }

    var longitudeUnwrapped: Double? {
        hasExplicitLongitude || longitude != 0 ? longitude : nil
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
        hasExplicitLatitude = value.latitude != nil
        hasExplicitLongitude = value.longitude != nil
    }
}
