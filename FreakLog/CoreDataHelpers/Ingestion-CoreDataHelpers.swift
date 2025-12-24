import CoreData

extension Ingestion: Comparable {
    public static func < (lhs: Ingestion, rhs: Ingestion) -> Bool {
        lhs.timeUnwrapped < rhs.timeUnwrapped
    }

    var timeUnwrapped: Date {
        time ?? Date()
    }

    var noteUnwrapped: String {
        note ?? ""
    }

    var substanceNameUnwrapped: String {
        substanceName ?? "Unknown"
    }

    var administrationRouteUnwrapped: AdministrationRoute {
        AdministrationRoute(rawValue: administrationRoute ?? "oral") ?? .oral
    }

    var administrationSiteUnwrapped: String {
        administrationSite ?? ""
    }

    var consumerNameUnwrapped: String {
        consumerName ?? ""
    }

    var doseUnwrapped: Double? {
        if dose == 0 {
            return nil
        } else {
            return dose
        }
    }

    var estimatedDoseStandardDeviationUnwrapped: Double? {
        if estimatedDoseStandardDeviation == 0 || !isEstimate {
            return nil
        } else {
            return estimatedDoseStandardDeviation
        }
    }

    private var lowerEstimate: Double? {
        guard let doseUnwrapped else {return nil}
        guard let estimatedDoseStandardDeviationUnwrapped else {return nil}
        return doseUnwrapped - estimatedDoseStandardDeviationUnwrapped
    }

    private var higherEstimate: Double? {
        guard let doseUnwrapped else {return nil}
        guard let estimatedDoseStandardDeviationUnwrapped else {return nil}
        return doseUnwrapped + estimatedDoseStandardDeviationUnwrapped
    }

    var pureSubstanceDose: Double? {
        if let customUnitDose {
            customUnitDose.calculatedDose
        } else {
            doseUnwrapped
        }
    }

    var pureSubstanceEstimatedDoseStandardDeviation: Double? {
        if let customUnitDose {
            customUnitDose.calculatedStandardDeviation
        } else {
            estimatedDoseStandardDeviationUnwrapped
        }
    }

    var customUnitDose: CustomUnitDose? {
        guard let doseUnwrapped, let customUnit else {return nil}
        return CustomUnitDose(
            dose: doseUnwrapped,
            isEstimate: isEstimate,
            estimatedStandardDeviation: estimatedDoseStandardDeviationUnwrapped,
            customUnit: customUnit)
    }

    var substance: Substance? {
        SubstanceRepo.shared.getSubstance(name: substanceNameUnwrapped)
    }

    var numberOfDots: Int? {
        substance?.getDose(for: administrationRouteUnwrapped)?.getNumDots(
            ingestionDose: pureSubstanceDose,
            ingestionUnits: pureUnits
        )
    }

    var pureUnits: String {
        if let customUnit {
            customUnit.originalUnitUnwrapped
        } else {
            unitsUnwrapped
        }
    }

    var unitsUnwrapped: String {
        if let units {
            return units
        } else {
            return ""
        }
    }

    var substanceColor: SubstanceColor {
        substanceCompanion?.color ?? .red
    }

    var webhookMessagesSorted: [WebhookMessage] {
        let set = webhookMessages as? Set<WebhookMessage> ?? []
        return set.sorted { lhs, rhs in
            let lDate = lhs.creationDate ?? Date.distantPast
            let rDate = rhs.creationDate ?? Date.distantPast
            return lDate < rDate
        }
    }

    static var knownDosePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "MDMA"
        ingestion.dose = 50
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.oral.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var estimatedDosePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Cocaine"
        ingestion.dose = 30
        ingestion.units = "mg"
        ingestion.isEstimate = true
        ingestion.estimatedDoseStandardDeviation = 5
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var unknownDosePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Cocaine"
        ingestion.dose = 0
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var notePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Cocaine"
        ingestion.dose = 30
        ingestion.units = "mg"
        ingestion.isEstimate = true
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = "This is a longer note that might not fit on one line and it needs to be able to handle this"
        return ingestion
    }

    static var customSubstancePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Customsubstance"
        ingestion.dose = 50
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.oral.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var customUnitPreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Ketamine"
        ingestion.dose = 2
        ingestion.customUnit = CustomUnit.previewSample
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var customUnitUnknownDosePreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Ketamine"
        ingestion.dose = 2
        ingestion.customUnit = CustomUnit.unknownDoseSample
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var estimatedCustomUnitPreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Ketamine"
        ingestion.dose = 2
        ingestion.customUnit = CustomUnit.estimatePreviewSample
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = ""
        return ingestion
    }

    static var estimatedQuantitativelyCustomUnitPreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Ketamine"
        ingestion.dose = 2
        ingestion.customUnit = CustomUnit.estimatedQuantitativelyPreviewSample
        ingestion.units = "mg"
        ingestion.isEstimate = false
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = "Quantitatively estimated custom unit"
        return ingestion
    }

    static var everythingEstimatedQuantitativelyPreviewSample: Ingestion {
        let ingestion = Ingestion(context: PersistenceController.preview.viewContext)
        ingestion.substanceName = "Ketamine"
        ingestion.dose = 3
        ingestion.customUnit = CustomUnit.estimatedQuantitativelyPreviewSample
        ingestion.units = "mg"
        ingestion.isEstimate = true
        ingestion.estimatedDoseStandardDeviation = 0.5
        ingestion.administrationRoute = AdministrationRoute.insufflated.rawValue
        ingestion.time = .now
        ingestion.note = "Everything estimated quantitatively"
        return ingestion
    }
}
