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
    let isHiddenInTimeline: Bool
    let stomachFullness: String?
    // The ID is local to the file. Older files only have a name.
    var formulationId: String?
    var formulationName: String?
    var formulationAmount: Double?

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
        case formulationName
        case formulationId
        case formulationAmount
        case isHiddenInTimeline
        case stomachFullness
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
        location: LocationCodable?,
        isHiddenInTimeline: Bool = false,
        stomachFullness: String? = nil
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
        self.isHiddenInTimeline = isHiddenInTimeline
        self.stomachFullness = stomachFullness
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        substanceName = try values.decode(String.self, forKey: .substanceName)
        time = try values.decodeMillis(forKey: .time)
        endTime = try values.decodeMillisIfPresent(forKey: .endTime)
        creationDate = try values.decodeMillisIfPresent(forKey: .creationDate)
        let routeString = try values.decode(String.self, forKey: .administrationRoute)
        if let route = AdministrationRoute(rawValue: routeString.lowercased()) {
            administrationRoute = route
        } else {
            throw try DecodingError.dataCorruptedError(in: decoder.unkeyedContainer(), debugDescription: "\(routeString) is not a valid route")
        }
        dose = try values.decodeIfPresent(Double.self, forKey: .dose)
        estimatedDoseStandardDeviation = try values.decodeIfPresent(Double.self, forKey: .estimatedDoseStandardDeviation)
        isDoseAnEstimate = try values.decode(Bool.self, forKey: .isDoseAnEstimate)
        units = try values.decodeIfPresent(String.self, forKey: .units) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        consumerName = try values.decodeIfPresent(String.self, forKey: .consumerName)
        customUnitId = try values.decodeIfPresent(Int32.self, forKey: .customUnitId)
        administrationSite = try values.decodeIfPresent(String.self, forKey: .administrationSite)
        location = try values.decodeIfPresent(LocationCodable.self, forKey: .location)
        formulationName = try values.decodeIfPresent(String.self, forKey: .formulationName)
        formulationId = try values.decodeIfPresent(String.self, forKey: .formulationId)
        formulationAmount = try values.decodeIfPresent(Double.self, forKey: .formulationAmount)
        isHiddenInTimeline = try values.decodeIfPresent(Bool.self, forKey: .isHiddenInTimeline) ?? false
        stomachFullness = try values.decodeIfPresent(String.self, forKey: .stomachFullness)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(substanceName, forKey: .substanceName)
        try container.encodeMillis(time, forKey: .time)
        try container.encodeMillis(endTime, forKey: .endTime)
        try container.encodeMillis(creationDate, forKey: .creationDate)
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
        try container.encodeIfPresent(formulationName, forKey: .formulationName)
        try container.encodeIfPresent(formulationId, forKey: .formulationId)
        try container.encodeIfPresent(formulationAmount, forKey: .formulationAmount)
        try container.encodeIfPresent(isHiddenInTimeline ? true : nil, forKey: .isHiddenInTimeline)
        try container.encodeIfPresent(stomachFullness, forKey: .stomachFullness)
    }
}

// Export and import mapping. The importer links companions, custom units, formulations and the experience.
extension IngestionCodable {
    init(
        _ ingestion: Ingestion,
        customUnitIds: [NSManagedObjectID: Int32],
        formulationIds: [NSManagedObjectID: String]
    ) throws {
        let unit = ingestion.customUnit
        let customUnitId = unit.flatMap { customUnitIds[$0.objectID] }
        if let unit, customUnitId == nil {
            throw JournalFileError.missingCustomUnit(String(unit.idForAndroid))
        }
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
            customUnitId: customUnitId,
            administrationSite: ingestion.administrationSite,
            location: ingestion.location.map(LocationCodable.init),
            isHiddenInTimeline: ingestion.isHiddenInTimeline,
            stomachFullness: ingestion.stomachFullness
        )
        if let formulation = ingestion.formulation {
            guard let id = formulationIds[formulation.objectID] else {
                throw JournalFileError.missingFormulation(formulation.nameUnwrapped)
            }
            formulationId = id
            formulationName = formulation.nameUnwrapped
            formulationAmount = ingestion.formulationAmount
        }
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
        ingestion.formulationAmount = formulationAmount ?? 0
        ingestion.isHiddenInTimeline = isHiddenInTimeline
        ingestion.stomachFullness = stomachFullness
        if let location = location ?? fallbackLocation {
            ingestion.location = ExperienceLocation.make(from: location, in: context)
        }
        return ingestion
    }
}
