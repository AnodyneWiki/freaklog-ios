import Foundation

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
}
