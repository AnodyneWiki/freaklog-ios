import CoreData

extension Ingestion: Comparable {
    static var confirmedPredicate: NSPredicate {
        // Optional for migration and CloudKit. Historical nulls are ordinary confirmed entries.
        NSPredicate(format: "isUnconfirmed == nil OR isUnconfirmed == NO")
    }

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

    var isHiddenFromTimeline: Bool {
        isHiddenInTimeline || substanceCompanion?.isHiddenInTimeline == true
    }

    var pendingConfirmationEntries: [Ingestion] {
        guard isUnconfirmed else { return [] }
        guard let confirmationBatchID, let experience else { return [self] }
        return experience.ingestionsSorted.filter {
            $0.isUnconfirmed && $0.confirmationBatchID == confirmationBatchID
        }
    }

    var inventoryArguments: FinishIngestionScreenArguments {
        FinishIngestionScreenArguments(
            substanceName: substanceNameUnwrapped,
            administrationRoute: administrationRouteUnwrapped,
            dose: doseUnwrapped,
            units: unitsUnwrapped,
            isEstimate: isEstimate,
            estimatedDoseStandardDeviation: estimatedDoseStandardDeviationUnwrapped,
            customUnit: customUnit,
            formulation: formulation,
            formulationAmount: formulationAmount
        )
    }

    var administrationSiteUnwrapped: String {
        administrationSite ?? ""
    }

    var consumerNameUnwrapped: String {
        consumerName ?? ""
    }

    // The user's own ingestion. Whitespace-only names also count as the user.
    var isMine: Bool {
        Self.storedConsumerName(consumerNameUnwrapped) == nil
    }

    // What to store for an entered consumer name: nil when it means the user themselves.
    static func storedConsumerName(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
    }

    // Inserts, updates or removes the ingestion's location to match the picked one.
    func setLocation(_ newLocation: Location?) {
        guard let context = managedObjectContext else { return }
        if let newLocation {
            if let location {
                location.update(from: newLocation)
            } else {
                location = ExperienceLocation.make(from: newLocation, in: context)
            }
        } else if let location {
            context.delete(location)
            self.location = nil
        }
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

    var roaDose: RoaDose? {
        PersistenceController.shared.resolvedDose(for: substanceNameUnwrapped, route: administrationRouteUnwrapped)
    }

    var numberOfDots: Int? {
        roaDose?.getNumDots(ingestionDose: pureSubstanceDose, ingestionUnits: pureUnits)
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
        substanceCompanion?.color ?? .fallback
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
