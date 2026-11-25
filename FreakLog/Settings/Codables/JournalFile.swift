import CoreData
import SwiftUI
import UniformTypeIdentifiers

enum JournalFileError: LocalizedError, Equatable {
    case noJournalData
    case duplicateCustomUnit(Int32)
    case duplicateFormulation(String)
    case missingCustomUnit(String)
    case missingFormulation(String)
    case tooManyCustomUnits

    var errorDescription: String? {
        switch self {
        case .noJournalData:
            "This file doesn’t contain a recognized journal."
        case .duplicateCustomUnit(let id):
            "The journal contains duplicate custom-unit ID \(id)."
        case .duplicateFormulation(let id):
            "The journal contains duplicate formulation ID \(id)."
        case .missingCustomUnit(let id):
            "An ingestion refers to a missing custom unit (\(id))."
        case .missingFormulation(let id):
            "An ingestion refers to a missing formulation (\(id))."
        case .tooManyCustomUnits:
            "The journal contains too many custom units to export."
        }
    }
}

struct JournalFile: FileDocument, Codable {
    static let readableContentTypes = [UTType.json]
    static let writableContentTypes = [UTType.json]
    let experiences: [ExperienceCodable]
    let substanceCompanions: [CompanionCodable]
    let customSubstances: [CustomSubstanceCodable]
    let customUnits: [CustomUnitCodable]
    let substanceDataOverrides: [SubstanceDataOverrideCodable]
    let formulations: [FormulationCodable]
    private(set) var transferOmissions: [String] = []

    init(
        experiences: [Experience],
        customSubstances: [CustomSubstance],
        customUnits: [CustomUnit],
        substanceOverrideRoas: [CustomRoa] = [],
        substanceOverrides: [SubstanceOverride] = [],
        formulations: [Formulation] = []
    ) throws {
        let customUnitIds = try Self.exportCustomUnitIds(customUnits)
        var formulationIds: [NSManagedObjectID: String] = [:]
        self.formulations = try formulations.map { formulation in
            if let id = formulationIds[formulation.objectID] {
                throw JournalFileError.duplicateFormulation(id)
            }
            let id = UUID().uuidString
            formulationIds[formulation.objectID] = id
            var record = FormulationCodable(formulation)
            record.id = id
            return record
        }
        self.experiences = try experiences.map {
            try ExperienceCodable($0, customUnitIds: customUnitIds, formulationIds: formulationIds)
        }
        // One color for each substance that was taken
        var substanceNames = Set<String>()
        substanceCompanions = experiences.flatMap(\.ingestionsSorted).compactMap { ingestion in
            guard substanceNames.insert(ingestion.substanceNameUnwrapped).inserted else { return nil }
            return CompanionCodable(
                substanceName: ingestion.substanceNameUnwrapped,
                color: ingestion.substanceColor,
                isHiddenInTimeline: ingestion.substanceCompanion?.isHiddenInTimeline == true
            )
        }
        self.customSubstances = customSubstances.map(CustomSubstanceCodable.init)
        self.customUnits = try customUnits.map { unit in
            guard let id = customUnitIds[unit.objectID] else {
                throw JournalFileError.missingCustomUnit(String(unit.idForAndroid))
            }
            return CustomUnitCodable(unit, id: id)
        }
        substanceDataOverrides = SubstanceDataOverrideCodable.grouped(substanceOverrideRoas, overrides: substanceOverrides)
        try validateReferences()
    }

    private static func exportCustomUnitIds(_ units: [CustomUnit]) throws -> [NSManagedObjectID: Int32] {
        var reserved = Set(units.map(\.idForAndroid))
        var claimed = Set<Int32>()
        var ids: [NSManagedObjectID: Int32] = [:]
        var candidate: Int32 = 1
        for unit in units {
            let preferred = unit.idForAndroid
            guard ids[unit.objectID] == nil else { throw JournalFileError.duplicateCustomUnit(preferred) }
            if claimed.insert(preferred).inserted {
                ids[unit.objectID] = preferred
            } else {
                // Reserve existing IDs before assigning replacements so subsequent units can keep theirs.
                while !reserved.insert(candidate).inserted {
                    candidate = candidate &+ 1
                    guard candidate != 1 else { throw JournalFileError.tooManyCustomUnits }
                }
                ids[unit.objectID] = candidate
            }
        }
        return ids
    }

    private func validateReferences() throws {
        var unitIds = Set<Int32>()
        for unit in customUnits where !unitIds.insert(unit.id).inserted {
            throw JournalFileError.duplicateCustomUnit(unit.id)
        }
        var formulationIds = Set<String>()
        for id in formulations.compactMap(\.id) where !formulationIds.insert(id).inserted {
            throw JournalFileError.duplicateFormulation(id)
        }
        for ingestion in experiences.lazy.flatMap(\.ingestions) {
            if let id = ingestion.customUnitId, !unitIds.contains(id) {
                throw JournalFileError.missingCustomUnit(String(id))
            }
            if let id = ingestion.formulationId, !formulationIds.contains(id) {
                throw JournalFileError.missingFormulation(id)
            }
        }
    }

    // Replaces the journal in a dedicated context so a failed save leaves the old journal intact.
    func replaceJournal(in context: NSManagedObjectContext) throws {
        do {
            try PersistenceController.stageJournalDeletion(in: context)
            insert(into: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        PersistenceController.purgeLocalHistory(in: context)
    }

    // Inserts everything in the file without saving.
    func insert(into context: NSManagedObjectContext) {
        var companions: [String: SubstanceCompanion] = [:]
        for companionCodable in substanceCompanions where companions[companionCodable.substanceName] == nil {
            companions[companionCodable.substanceName] = companionCodable.insert(into: context)
        }
        var customUnitsById: [Int32: CustomUnit] = [:]
        for customUnitCodable in customUnits {
            customUnitsById[customUnitCodable.id] = customUnitCodable.insert(into: context)
        }
        let nameCounts = Dictionary(grouping: formulations, by: \.name)
        var formulationsById: [String: Formulation] = [:]
        var formulationsByName: [String: Formulation] = [:]
        for formulationCodable in formulations {
            let formulation = formulationCodable.insert(into: context)
            if let id = formulationCodable.id { formulationsById[id] = formulation }
            // Old files can only identify a formulation if its name is unique.
            if nameCounts[formulationCodable.name]?.count == 1 {
                formulationsByName[formulationCodable.name] = formulation
            }
        }
        for experienceCodable in experiences {
            _ = experienceCodable.insert(
                into: context,
                companion: { substanceName in
                    if let companion = companions[substanceName] {
                        return companion
                    }
                    let color = SubstanceColor.suggested(avoiding: companions.values.map(\.color))
                    let companion = CompanionCodable(substanceName: substanceName, color: color).insert(into: context)
                    companions[substanceName] = companion
                    return companion
                },
                customUnits: customUnitsById,
                formulationsById: formulationsById,
                formulationsByName: formulationsByName
            )
        }
        substanceDataOverrides.forEach { $0.insert(into: context) }
        customSubstances.forEach { _ = $0.insert(into: context) }
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            self = try Self.read(data)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return FileWrapper(regularFileWithContents: data)
    }



    enum CodingKeys: String, CodingKey {
        case experiences
        case substanceCompanions
        case customSubstances
        case customUnits
        case substanceDataOverrides
        case formulations
    }

    private enum HeaderKeys: String, CodingKey {
        case format, formatVersion, exportSource
    }

    private struct Header: Decodable {
        let exportSource: String?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: HeaderKeys.self)
            guard !values.contains(.format), !values.contains(.formatVersion) else {
                throw JournalBackupError.unrecognizedFormat
            }
            exportSource = values.contains(.exportSource) ? try values.decode(String.self, forKey: .exportSource) : nil
        }
    }

    static func read(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard let source = header.exportSource else {
            let raw = try decoder.decode([String: JSONValue].self, from: data)
            let converted = try AndroidJournalTransfer.imported(raw)
            var journal = try decoder.decode(Self.self, from: JSONEncoder().encode(converted.fields))
            journal.transferOmissions = converted.omissions
            return journal
        }
        guard supportsModernJournalSource(source) else {
            throw JournalBackupError.unrecognizedFormat
        }
        var journal = try decoder.decode(Self.self, from: Version12Journal.convert(data))
        if source.hasPrefix("iOS Journal 18.") {
            journal.transferOmissions = [
                "PW Journal 18 tag definitions, blend policies and other version-specific settings may be unavailable."
            ]
        }
        return journal
    }

    func androidTransferData() throws -> Data {
        let fields = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(self))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(AndroidJournalTransfer.exported(fields))
    }

    private static func supportsModernJournalSource(_ source: String) -> Bool {
        if source == "iOS Journal" || source == "Android Journal" { return true }
        // Recent iOS exports can append an app version to the source marker.
        let prefix = "iOS Journal "
        guard source.hasPrefix(prefix) else { return false }
        let version = source.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(version.count), let major = Int(version[0]), (12...18).contains(major) else {
            return false
        }
        return version.allSatisfy { component in
            !component.isEmpty && component.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    init(from decoder: Decoder) throws {
        guard try Header(from: decoder).exportSource == nil else { throw JournalBackupError.unrecognizedFormat }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let hasExperiences = values.contains(.experiences)
        experiences = hasExperiences ? try values.decode([ExperienceCodable].self, forKey: .experiences) : []
        substanceCompanions = try values.decodeIfPresent([CompanionCodable].self, forKey: .substanceCompanions) ?? []
        customSubstances = try values.decodeIfPresent([CustomSubstanceCodable].self, forKey: .customSubstances) ?? []
        customUnits = try values.decodeIfPresent([CustomUnitCodable].self, forKey: .customUnits) ?? []
        substanceDataOverrides = try values.decodeIfPresent([SubstanceDataOverrideCodable].self, forKey: .substanceDataOverrides) ?? []
        formulations = try values.decodeIfPresent([FormulationCodable].self, forKey: .formulations) ?? []
        guard hasExperiences || !substanceCompanions.isEmpty || !customSubstances.isEmpty || !customUnits.isEmpty
            || !substanceDataOverrides.isEmpty || !formulations.isEmpty else {
            throw JournalFileError.noJournalData
        }
        try validateReferences()
    }
}

/// The headerless JournalExport shape used by FreakLog Android 11.36.
private enum AndroidJournalTransfer {
    typealias Fields = [String: JSONValue]

    private static let fullnessValues: Set<String> = ["EMPTY", "QUARTERFULL", "HALFFULL", "FULL", "VERYFULL"]

    static func imported(_ fields: Fields) throws -> (fields: Fields, omissions: [String]) {
        var fields = fields
        var omissions: [String] = []
        let unsupported: [(String, String)] = [
            ("customRecipes", "Recipes"), ("customFormulations", "Release profiles"), ("reminders", "Reminders"),
            ("webhooks", "Webhooks"), ("intakeLimits", "Intake limits"), ("substanceGroups", "Substance groups"),
            ("customSubstanceDetails", "Advanced substance profiles")
        ]
        for (key, label) in unsupported where fields[key]?.array?.isEmpty == false {
            omissions.append(label)
        }
        let importedAt = Double(Date.now.millisecondsSince1970)
        fields["customUnits"] = try rewrite(fields["customUnits"]) { unit in
            var unit = unit
            // Kotlin defaults an omitted creation date to the time the record is decoded.
            if unit["creationDate"] == nil { unit["creationDate"] = .number(importedAt) }
            return unit
        }
        fields["substanceCompanions"] = try rewrite(fields["substanceCompanions"]) { companion in
            var companion = companion
            // Android omits its default BLUE value when encoding a companion.
            if companion["color"] == nil, companion["colorHex"] == nil { companion["color"] = .string("BLUE") }
            return importedColor(companion)
        }
        var omittedPressure = false
        var omittedIngestionDetails = false
        fields["experiences"] = try rewrite(fields["experiences"]) { experience in
            var experience = experience
            if experience["bloodPressure"]?.array?.isEmpty == false { omittedPressure = true }
            experience["timedNotes"] = try rewrite(experience["timedNotes"], importedColor)
            experience["ingestions"] = try rewrite(experience["ingestions"]) { ingestion in
                var ingestion = ingestion
                if ["customFormulationId", "saltForm", "category"].contains(where: {
                    ingestion[$0].map { $0 != .null } == true
                }) {
                    omittedIngestionDetails = true
                }
                // A named release profile is not a FreakLog iOS blend.
                if ingestion["customFormulationId"] != nil {
                    ingestion.removeValue(forKey: "formulationName")
                }
                return ingestion
            }
            return experience
        }
        if omittedPressure { omissions.append("Blood pressure records") }
        if omittedIngestionDetails { omissions.append("Ingestion release profiles, salt forms or categories") }
        if fields["customUnits"]?.array?.contains(where: { $0["defaultCategory"]?.string != nil }) == true
            || fields["substanceCompanions"]?.array?.contains(where: { $0["defaultCategory"]?.string != nil }) == true {
            omissions.append("Default ingestion categories")
        }
        return (fields, omissions)
    }

    static func exported(_ fields: Fields) throws -> Fields {
        var fields = fields
        fields.removeValue(forKey: "substanceDataOverrides")
        fields.removeValue(forKey: "formulations")
        fields["customSubstances"] = try rewrite(fields["customSubstances"]) { substance in
            var substance = substance
            substance.removeValue(forKey: "roas")
            return substance
        }
        fields["substanceCompanions"] = try rewrite(fields["substanceCompanions"], exportedColor)
        fields["experiences"] = try rewrite(fields["experiences"]) { experience in
            var experience = experience
            experience["timedNotes"] = try rewrite(experience["timedNotes"], exportedColor)
            experience["ratings"] = try rewrite(experience["ratings"]) { rating in
                var rating = rating
                rating.removeValue(forKey: "isHiddenInTimeline")
                return rating
            }
            if let ingestions = experience["ingestions"]?.array {
                experience["ingestions"] = .array(ingestions.filter { $0["isUnconfirmed"]?.bool != true })
            }
            experience["ingestions"] = try rewrite(experience["ingestions"]) { ingestion in
                var ingestion = ingestion
                for key in ["location", "formulationId", "formulationName", "formulationAmount",
                            "isHiddenInTimeline", "isUnconfirmed"] {
                    ingestion.removeValue(forKey: key)
                }
                if let fullness = ingestion["stomachFullness"]?.string {
                    let name = fullness.uppercased().filter(\.isLetter)
                    ingestion["stomachFullness"] = fullnessValues.contains(name) ? .string(name) : nil
                }
                return ingestion
            }
            return experience
        }
        return fields
    }

    private static func importedColor(_ fields: Fields) -> Fields {
        guard let color = fields["color"]?.string,
              color.hasPrefix("CUSTOM_"), color.utf8.count == 15,
              color.dropFirst(7).allSatisfy(\.isHexDigit),
              let exact = SubstanceColor(hex: String(color.suffix(6))) else { return fields }
        var fields = fields
        fields["color"] = .string(exact.rawValue)
        return fields
    }

    private static func exportedColor(_ fields: Fields) -> Fields {
        var fields = fields
        if let exact = fields.removeValue(forKey: "colorHex")?.string {
            fields["color"] = .string("CUSTOM_FF" + exact.dropFirst())
        }
        fields.removeValue(forKey: "isHiddenInTimeline")
        return fields
    }

    private static func rewrite(_ value: JSONValue?, _ transform: (Fields) throws -> Fields) throws -> JSONValue? {
        guard let value, let rows = value.array else { return value }
        return .array(try rows.map { row in
            guard let fields = row.object else { return row }
            return .object(try transform(fields))
        })
    }
}

// PW Journal v12 represents custom units as definitions that can contain several doses or refer to other units.
private struct Version12Journal {
    private typealias Fields = [String: JSONValue]

    private enum ImportError: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let reason): "Couldn't import this PW Journal file. \(reason)"
            }
        }
    }

    private struct Quantity {
        var amount: Double?
        var isEstimate: Bool
        var deviation: Double?

        init(_ fields: Fields) throws {
            amount = try Version12Journal.number(fields["dose"] ?? fields["amount"], key: "dose")
            deviation = try Version12Journal.number(fields["estimatedDoseStandardDeviation"], key: "estimatedDoseStandardDeviation")
            isEstimate = fields["isDoseAnEstimate"]?.bool ?? fields["isEstimate"]?.bool ?? (deviation != nil)
        }

        func multiplied(by quantity: Self) throws -> Self {
            var result = self
            result.isEstimate = isEstimate || quantity.isEstimate
            guard let amount, let multiplier = quantity.amount else {
                result.amount = nil
                result.deviation = nil
                return result
            }
            let product = amount * multiplier
            let productDeviation = CustomUnitDose.productDeviation(
                amount: multiplier, amountDeviation: quantity.isEstimate ? quantity.deviation : nil,
                dosePerUnit: amount, doseDeviation: isEstimate ? deviation : nil)
            guard product.isFinite, productDeviation?.isFinite != false else {
                throw ImportError.invalid("A custom-unit dose is out of range.")
            }
            result.amount = product
            result.deviation = productDeviation
            return result
        }
    }

    private struct Ingredient {
        let name: String
        var route: AdministrationRoute?
        let units: String
        var quantity: Quantity

        init(name: String, fields: Fields, units: String) throws {
            self.name = name
            self.units = units
            route = try Version12Journal.route(fields["administrationRoute"])
            quantity = try Quantity(fields)
        }

        func formulationComponent(defaultRoute: AdministrationRoute) -> FormulationCodable.Component {
            FormulationCodable.Component(
                substanceName: name, administrationRoute: route ?? defaultRoute, dose: quantity.amount, units: units,
                isEstimate: quantity.isEstimate, estimatedDoseStandardDeviation: quantity.deviation)
        }
    }

    private enum Target {
        case unit(id: Int32, name: String, units: String, route: AdministrationRoute?)
        case formulation(id: String, name: String, ingredients: [Ingredient], route: AdministrationRoute?)
    }

    private let definitions: [String: Fields]
    private var resolved: [String: [Ingredient]] = [:]
    private var resolving = Set<String>()

    static func convert(_ data: Data) throws -> Data {
        let original = try JSONDecoder().decode(Fields.self, from: data)
        let rows = try records(original["customUnits"], key: "customUnits")
        var definitions: [String: Fields] = [:]
        var order: [String] = []
        for row in rows {
            guard let id = try identifier(row["id"]) else { throw ImportError.invalid("A custom unit is missing its ID.") }
            guard definitions.updateValue(row, forKey: id) == nil else {
                throw ImportError.invalid("Custom-unit ID \(id) occurs more than once.")
            }
            order.append(id)
        }
        var converter = Self(definitions: definitions)
        return try JSONEncoder().encode(converter.convert(original, unitIds: order))
    }

    private mutating func convert(_ original: Fields, unitIds: [String]) throws -> Fields {
        var root = original
        root.removeValue(forKey: "exportSource")
        let experiences = try Self.records(root["experiences"], key: "experiences")
        let ingestions = try experiences.map { try Self.records($0["ingestions"], key: "ingestions") }
        var observedRoutes: [String: AdministrationRoute] = [:]
        for record in ingestions.joined() {
            if let id = try Self.identifier(record["customUnitId"]),
               let route = try Self.route(record["administrationRoute"]), observedRoutes[id] == nil {
                observedRoutes[id] = route
            }
        }

        var customs = try Self.records(root["customSubstances"], key: "customSubstances")
        var companions = try Self.records(root["substanceCompanions"], key: "substanceCompanions")
        var customNames = Set(customs.compactMap { $0["name"]?.string })
        var companionNames = Set(companions.compactMap { $0["substanceName"]?.string })
        var units: [CustomUnitCodable] = []
        var formulations = try Self.records(root["formulations"], key: "formulations").map(JSONValue.object)
        var targets: [String: Target] = [:]

        for (index, id) in unitIds.enumerated() {
            guard let definition = definitions[id], let name = definition["name"]?.string, !name.isEmpty else {
                throw ImportError.invalid("Custom unit \(id) is missing its name.")
            }
            let ingredients = try resolve(id)
            let route = try Self.route(definition["administrationRoute"])
            let defaultRoute = route ?? observedRoutes[id] ?? .oral
            let unit = definition["unit"]?.string ?? ""
            let note = definition["note"]?.string ?? ""
            let created = definition["creationDate"]?.number.flatMap(Int64.init(exactly:))
                .map(Date.init(millisecondsSince1970:)) ?? .now
            if ingredients.count == 1, let ingredient = ingredients.first {
                guard let localId = Int32(exactly: index + 1) else { throw ImportError.invalid("Too many custom units.") }
                units.append(CustomUnitCodable(
                    id: localId, substanceName: ingredient.name, name: name, creationDate: created,
                    administrationRoute: ingredient.route ?? defaultRoute, dose: ingredient.quantity.amount,
                    estimatedDoseStandardDeviation: ingredient.quantity.deviation, isEstimate: ingredient.quantity.isEstimate,
                    isArchived: definition["isArchived"]?.bool ?? false, unit: unit, unitPlural: definition["unitPlural"]?.string,
                    originalUnit: ingredient.units, note: note))
                targets[id] = .unit(id: localId, name: ingredient.name, units: unit, route: ingredient.route ?? route)
                if let color = definition["color"]?.string, companionNames.insert(ingredient.name).inserted {
                    companions.append(["substanceName": .string(ingredient.name), "color": .string(color)])
                }
                if ingredient.name == name, definition["substanceName"]?.string == nil,
                   try Self.records(definition["doseComponents"], key: "doseComponents").isEmpty,
                   customNames.insert(name).inserted {
                    customs.append(["name": .string(name), "units": .string(unit), "description": .string(note)])
                }
            } else {
                let localId = UUID().uuidString
                let formulation = FormulationCodable(
                    name: name, note: note, creationDate: created,
                    components: ingredients.map { $0.formulationComponent(defaultRoute: defaultRoute) }, id: localId)
                formulations.append(try JSONValue(encoding: formulation))
                targets[id] = .formulation(id: localId, name: name, ingredients: ingredients, route: route)
            }
        }

        if let value = root["experiences"], value != .null {
            root["experiences"] = .array(try zip(experiences, ingestions).map { experience, records in
                var experience = experience
                experience["ingestions"] = .array(try records.flatMap { try Self.convertIngestion($0, using: targets) })
                return .object(experience)
            })
        }
        root["customSubstances"] = .array(customs.map(JSONValue.object))
        root["substanceCompanions"] = .array(companions.map(JSONValue.object))
        root["customUnits"] = try JSONValue(encoding: units)
        root["formulations"] = .array(formulations)
        return root
    }

    private mutating func resolve(_ id: String) throws -> [Ingredient] {
        if let ingredients = resolved[id] { return ingredients }
        guard resolving.insert(id).inserted else { throw ImportError.invalid("Custom unit \(id) refers back to itself.") }
        defer { resolving.remove(id) }
        guard let fields = definitions[id], let name = fields["name"]?.string, !name.isEmpty else {
            throw ImportError.invalid("Custom unit \(id) is missing.")
        }
        let components = try Self.records(fields["doseComponents"], key: "doseComponents")
        var ingredients: [Ingredient] = []
        for component in components {
            if let nested = try Self.identifier(component["customUnitId"]) {
                let quantity = try Quantity(component)
                let route = try Self.route(component["administrationRoute"])
                ingredients += try resolve(nested).map { ingredient in
                    var ingredient = ingredient
                    ingredient.route = route ?? ingredient.route
                    ingredient.quantity = try ingredient.quantity.multiplied(by: quantity)
                    return ingredient
                }
            } else {
                guard let substance = component["substanceName"]?.string, !substance.isEmpty else {
                    throw ImportError.invalid("A component of \(name) is missing its substance name.")
                }
                let units = component["units"]?.string ?? component["unit"]?.string ?? component["originalUnit"]?.string ?? ""
                ingredients.append(try Ingredient(name: substance, fields: component, units: units))
            }
        }
        if ingredients.isEmpty {
            let units = fields["originalUnit"]?.string ?? ""
            ingredients = [try Ingredient(name: fields["substanceName"]?.string ?? name, fields: fields, units: units)]
        }
        resolved[id] = ingredients
        return ingredients
    }

    private static func convertIngestion(_ original: Fields, using targets: [String: Target]) throws -> [JSONValue] {
        var ingestion = original
        let quantity = try Quantity(ingestion)
        ingestion["isDoseAnEstimate"] = .bool(quantity.isEstimate)
        guard let id = try identifier(ingestion["customUnitId"]) else {
            ingestion["substanceName"] = .string(ingestion["substanceName"]?.string ?? "Unknown Substance")
            if ingestion["dose"] == nil { ingestion["dose"] = quantity.amount.map(JSONValue.number) ?? .null }
            return [.object(ingestion)]
        }
        guard let target = targets[id] else { throw ImportError.invalid("An ingestion refers to missing custom unit \(id).") }
        let ingestionRoute = try route(ingestion["administrationRoute"])
        switch target {
        case let .unit(localId, name, units, unitRoute):
            guard let route = ingestionRoute ?? unitRoute else {
                throw ImportError.invalid("An ingestion is missing its administration route.")
            }
            ingestion["customUnitId"] = .number(Double(localId))
            ingestion["substanceName"] = .string(name)
            ingestion["dose"] = quantity.amount.map(JSONValue.number) ?? .null
            ingestion["units"] = .string(units)
            ingestion["administrationRoute"] = .string(route.rawValue)
            return [.object(ingestion)]
        case let .formulation(localId, name, ingredients, unitRoute):
            ingestion.removeValue(forKey: "customUnitId")
            ingestion["formulationId"] = .string(localId)
            ingestion["formulationName"] = .string(name)
            ingestion["formulationAmount"] = quantity.amount.map(JSONValue.number) ?? .null
            return try ingredients.map { ingredient in
                guard let route = ingredient.route ?? ingestionRoute ?? unitRoute else {
                    throw ImportError.invalid("A formulation ingestion is missing an administration route.")
                }
                var record = ingestion
                let dose = try ingredient.quantity.multiplied(by: quantity)
                record["substanceName"] = .string(ingredient.name)
                record["administrationRoute"] = .string(route.rawValue)
                record["units"] = .string(ingredient.units)
                record["dose"] = dose.amount.map(JSONValue.number) ?? .null
                record["isDoseAnEstimate"] = .bool(dose.isEstimate)
                record["estimatedDoseStandardDeviation"] = dose.deviation.map(JSONValue.number) ?? .null
                return .object(record)
            }
        }
    }

    private static func records(_ value: JSONValue?, key: String) throws -> [Fields] {
        guard let value, value != .null else { return [] }
        guard let array = value.array else { throw ImportError.invalid("\(key) must be a list.") }
        return try array.map {
            guard let object = $0.object else { throw ImportError.invalid("A record in \(key) isn't an object.") }
            return object
        }
    }

    private static func identifier(_ value: JSONValue?) throws -> String? {
        guard let value, value != .null else { return nil }
        if let id = value.number.flatMap(Int64.init(exactly:)) { return String(id) }
        if let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return Int64(text).map(String.init) ?? text
        }
        throw ImportError.invalid("A custom-unit ID can't be read.")
    }

    private static func route(_ value: JSONValue?) throws -> AdministrationRoute? {
        guard let value, value != .null else { return nil }
        guard let text = value.string, let route = AdministrationRoute(rawValue: text.lowercased()) else {
            throw ImportError.invalid("An administration route isn't supported.")
        }
        return route
    }

    private static func number(_ value: JSONValue?, key: String) throws -> Double? {
        guard let value, value != .null else { return nil }
        guard let number = value.number, number.isFinite else { throw ImportError.invalid("A \(key) value can't be read.") }
        return number
    }
}
