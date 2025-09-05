import Foundation

extension CustomUnit {
    var nameUnwrapped: String {
        name ?? ""
    }

    var creationDateUnwrapped: Date {
        creationDate ?? .now
    }

    var administrationRouteUnwrapped: AdministrationRoute {
        AdministrationRoute(rawValue: administrationRoute ?? "oral") ?? .oral
    }

    var doseUnwrapped: Double? {
        if dose == 0 {
            return nil
        } else {
            return dose
        }
    }

    var originalUnitUnwrapped: String {
        originalUnit ?? ""
    }

    var substanceNameUnwrapped: String {
        substanceName ?? ""
    }

    var substance: Substance? {
        SubstanceRepo.shared.getSubstance(name: substanceNameUnwrapped)
    }

    var roaDose: RoaDose? {
        substance?.getDose(for: administrationRouteUnwrapped)
    }

    var noteUnwrapped: String {
        note ?? ""
    }

    var estimatedDoseStandardDeviationUnwrapped: Double? {
        if estimatedDoseStandardDeviation == 0 || !isEstimate {
            return nil
        } else {
            return estimatedDoseStandardDeviation
        }
    }

    var pluralizableUnit: PluralizableUnit {
        if let pluralUnitUnwrap = unitPlural {
            return PluralizableUnit(singular: unitUnwrapped, plural: pluralUnitUnwrap)
        } else {
            if !unitUnwrapped.hasSuffix("s") && unitUnwrapped != "mg" && unitUnwrapped != "g" && unitUnwrapped != "ml" {
                return PluralizableUnit(singular: unitUnwrapped, plural: unitUnwrapped + "s")
            } else {
                return PluralizableUnit(singular: unitUnwrapped, plural: unitUnwrapped)
            }
        }
    }

    var unitUnwrapped: String {
        unit ?? ""
    }

    var minInfo: CustomUnitMinInfo {
        CustomUnitMinInfo(dosePerUnit: doseUnwrapped, unit: unitUnwrapped)
    }

    var ingestionsUnwrapped: [Ingestion] {
        ingestions?.allObjects as? [Ingestion] ?? []
    }

    var doseOfOneUnitDescription: String {
        if let doseUnwrapped {
            if isEstimate {
                if let estimatedDoseStandardDeviationUnwrapped {
                    return "\(doseUnwrapped.formatted())±\(estimatedDoseStandardDeviationUnwrapped.formatted()) \(originalUnitUnwrapped)"
                } else {
                    return "~\(doseUnwrapped.formatted()) \(originalUnitUnwrapped)"
                }
            } else {
                return "\(doseUnwrapped.formatted()) \(originalUnitUnwrapped)"
            }
        } else {
            return "Unknown dose"
        }
    }

    var color: SubstanceColor? {
        let fetchRequest = SubstanceCompanion.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "substanceName == %@", substanceNameUnwrapped)
        let companions = try? PersistenceController.shared.viewContext.fetch(fetchRequest)
        return companions?.first?.color
    }

    static var previewSample: CustomUnit {
        let customUnit = CustomUnit(context: PersistenceController.preview.viewContext)
        customUnit.name = "Spoon"
        customUnit.substanceName = "Ketamine"
        customUnit.originalUnit = "mg"
        customUnit.unit = "scoop"
        customUnit.isEstimate = false
        customUnit.dose = 30
        customUnit.note = "Some random notes"
        return customUnit
    }

    static var unknownDoseSample: CustomUnit {
        let customUnit = CustomUnit(context: PersistenceController.preview.viewContext)
        customUnit.name = "Line"
        customUnit.substanceName = "Ketamine"
        customUnit.originalUnit = "mg"
        customUnit.unit = "line"
        customUnit.dose = 0
        customUnit.note = "Some random notes"
        return customUnit
    }

    static var estimatePreviewSample: CustomUnit {
        let customUnit = CustomUnit(context: PersistenceController.preview.viewContext)
        customUnit.name = "Estimated"
        customUnit.substanceName = "Ketamine"
        customUnit.originalUnit = "mg"
        customUnit.unit = "line"
        customUnit.dose = 20
        customUnit.isEstimate = true
        customUnit.note = "Some random notes"
        return customUnit
    }

    static var estimatedQuantitativelyPreviewSample: CustomUnit {
        let customUnit = CustomUnit(context: PersistenceController.preview.viewContext)
        customUnit.name = "Estimated Quantitatively"
        customUnit.substanceName = "Ketamine"
        customUnit.originalUnit = "mg"
        customUnit.unit = "line"
        customUnit.dose = 20
        customUnit.isEstimate = true
        customUnit.estimatedDoseStandardDeviation = 2
        customUnit.note = "Some random notes"
        return customUnit
    }
}

struct PluralizableUnit {
    // e.g. pill
    let singular: String
    // e.g. pills
    let plural: String
}
