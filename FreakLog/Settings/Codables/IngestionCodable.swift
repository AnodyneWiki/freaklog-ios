import CoreData
import Foundation

struct IngestionCodable: Codable {
    let substanceName: String
    let time: Date
    let endTime: Date?
    let creationDate: Date?
    let administrationRoute: AdministrationRoute
    let dose: Double?
    let estimatedDoseStandardDeviation: Double?
    let isDoseAnEstimate: Bool
    let units: String
    let notes: String
    let consumerName: String?
    let customUnitId: Int32?
    let administrationSite: String?
    let location: LocationCodable?

    enum CodingKeys: String, CodingKey {
        case substanceName
        case time
        case endTime
        case creationDate
        case administrationRoute
        case dose
        case estimatedDoseStandardDeviation
        case isDoseAnEstimate
        case units
        case notes
        case consumerName
        case customUnitId
        case administrationSite
        case location
    }

    init(
        substanceName: String,
        time: Date,
        endTime: Date?,
        creationDate: Date?,
        administrationRoute: AdministrationRoute,
        dose: Double?,
        estimatedDoseStandardDeviation: Double?,
        isDoseAnEstimate: Bool,
        units: String,
        notes: String,
        consumerName: String?,
        customUnitId: Int32?,
        administrationSite: String?,
        location: LocationCodable?
    ) {
        self.substanceName = substanceName
        self.time = time
        self.endTime = endTime
        self.creationDate = creationDate
        self.administrationRoute = administrationRoute
        self.dose = dose
        self.estimatedDoseStandardDeviation =                         estimatedDoseStandardDeviation
        self.isDoseAnEstimate = isDoseAnEstimate
        self.units = units
        self.notes = notes
        self.consumerName = consumerName
        self.customUnitId = customUnitId
        self.administrationSite = administrationSite
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try values.decode(String.self, forKey: .substanceName)
        let timeMillis = try values.decode(UInt64.self, forKey: .time)
        time = getDateFromMillis(millis: timeMillis)
        if let endTimeMillis = try values.decodeIfPresent(UInt64.self, forKey: .endTime) {
            endTime = getDateFromMillis(millis: endTimeMillis)
        } else {
            endTime = nil
        }
        if let creationMillis = try values.decodeIfPresent(UInt64.self, forKey: .creationDate) {
            creationDate = getDateFromMillis(millis: creationMillis)
        } else {
            creationDate = nil
        }
        let routeString = try values.decode(String.self, forKey: .administrationRoute)
        if let route = AdministrationRoute(rawValue: routeString.lowercased()) {
            administrationRoute = route
        } else {
            throw try DecodingError.dataCorruptedError(in: decoder.unkeyedContainer(), debugDescription: "\(routeString) is not a valid route")
        }
        dose = try values.decodeIfPresent(Double.self, forKey: .dose)
        estimatedDoseStandardDeviation = try values.decodeIfPresent(Double.self, forKey: .estimatedDoseStandardDeviation)
        isDoseAnEstimate = try values.decode(Bool.self, forKey: .isDoseAnEstimate)
        units = try values.decode(String.self, forKey: .units)
        notes = try values.decode(String.self, forKey: .notes)
        consumerName = try values.decodeIfPresent(String.self, forKey: .consumerName)
        customUnitId = try values.decodeIfPresent(Int32.self, forKey: .customUnitId)
        administrationSite = try values.decodeIfPresent(String.self, forKey: .administrationSite)
        location = try values.decodeIfPresent(LocationCodable.self, forKey: .location)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(substanceName, forKey: .substanceName)
        try container.encode(UInt64(time.timeIntervalSince1970) * 1000, forKey: .time)
        if let endTime {
            try container.encode(UInt64(endTime.timeIntervalSince1970) * 1000, forKey: .endTime)
        } else {
            let endTimeMillis: UInt64? = nil
            try container.encode(endTimeMillis, forKey: .endTime)
        }
        if let creationDate {
            try container.encode(UInt64(creationDate.timeIntervalSince1970) * 1000, forKey: .creationDate)
        } else {
            let creationMillis: UInt64? = nil
            try container.encode(creationMillis, forKey: .creationDate)
        }
        try container.encode(administrationRoute.rawValue.uppercased(), forKey: .administrationRoute)
        try container.encode(dose, forKey: .dose)
        try container.encode(estimatedDoseStandardDeviation, forKey: .estimatedDoseStandardDeviation)
        try container.encode(isDoseAnEstimate, forKey: .isDoseAnEstimate)
        try container.encode(units, forKey: .units)
        try container.encode(notes, forKey: .notes)
        try container.encode(consumerName, forKey: .consumerName)
        try container.encode(customUnitId, forKey: .customUnitId)
        try container.encode(administrationSite, forKey: .administrationSite)
        try container.encode(location, forKey: .location)
    }
}

// Export and import mapping. The importer links companions, custom units and the experience.
extension IngestionCodable {
    init(_ ingestion: Ingestion) {
        self.init(
            substanceName: ingestion.substanceNameUnwrapped,
            time: ingestion.timeUnwrapped,
            endTime: ingestion.endTime,
            creationDate: ingestion.creationDate,
            administrationRoute: ingestion.administrationRouteUnwrapped,
            dose: ingestion.doseUnwrapped,
            estimatedDoseStandardDeviation: ingestion.estimatedDoseStandardDeviationUnwrapped,
            isDoseAnEstimate: ingestion.isEstimate,
            units: ingestion.unitsUnwrapped,
            notes: ingestion.noteUnwrapped,
            consumerName: ingestion.consumerName,
            customUnitId: ingestion.customUnit?.idForAndroid,
            administrationSite: ingestion.administrationSite,
            location: ingestion.location.map(LocationCodable.init)
        )
    }

    // An older export only has a location on the experience, which then goes to each of its ingestions
    func insert(into context: NSManagedObjectContext, fallbackLocation: LocationCodable?) -> Ingestion {
        let ingestion = Ingestion(context: context)
        ingestion.identifier = UUID()
        ingestion.substanceName = substanceName
        ingestion.time = time
        ingestion.endTime = endTime
        ingestion.creationDate = creationDate
        ingestion.administrationRoute = administrationRoute.rawValue
        ingestion.dose = dose ?? 0
        ingestion.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation ?? 0
        ingestion.isEstimate = isDoseAnEstimate
        ingestion.units = units
        ingestion.note = notes
        ingestion.consumerName = consumerName
        ingestion.administrationSite = administrationSite
        if let location = location ?? fallbackLocation {
            ingestion.location = ExperienceLocation.make(from: location, in: context)
        }
        return ingestion
    }
}
