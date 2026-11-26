import CoreData
import SwiftUI

// MARK: - EditIngestionScreen

struct EditIngestionScreen: View {
    @ObservedObject var ingestion: Ingestion
    @State private var timelineVisibility = Ingestion.TimelineVisibility.substanceDefault
    @State private var time = Date()
    @State private var endTime = Date().addingTimeInterval(30*60)
    @State private var dose: Double?
    @State private var units: String = "mg"
    @State private var isEstimate = false
    @State private var estimatedDoseStandardDeviation: Double?
    @State private var note = ""
    @State private var consumerName = ""
    @State private var selectedCustomUnit: CustomUnit? = nil
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var siteSelection = AdministrationSiteSelection()
    @State private var correctedSubstance: AddIngestionSubstance?
    @State private var correctedRoute: AdministrationRoute?
    @State private var stockContainerID: NSManagedObjectID?
    @State private var sendConfirmationWebhooks = false
    @State private var correctionRequest: EditRequest?

    private enum EditRequest: String, Identifiable {
        case save, confirm
        var id: Self { self }
    }

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    @State private var sheetToShow: SheetOption?

    enum SheetOption: Identifiable {
        case editLocation
        case editConsumer
        case correctSubstance

        var id: Self {
            self
        }
    }

    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    var customUnits: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest())
    private var webhookPresets: FetchedResults<WebhookPreset>

    private var substanceName: String { correctedSubstance?.name ?? ingestion.substanceNameUnwrapped }
    private var route: AdministrationRoute { correctedRoute ?? ingestion.administrationRouteUnwrapped }
    private var correctsIdentity: Bool {
        substanceName != ingestion.substanceNameUnwrapped || route != ingestion.administrationRouteUnwrapped
    }

    private var filteredCustomUnit: [CustomUnit] {
        customUnits.filter { unit in
            unit.substanceNameUnwrapped == substanceName && unit.administrationRouteUnwrapped == route
        }
    }

    private var roaDose: RoaDose? {
        PersistenceController.shared.resolvedDose(for: substanceName, route: route)
    }

    @State private var experiencesWithinLargerRange: [Experience] = []
    @State private var wantsToForceNewExperience = false
    @State private var selectedExperience: Experience?

    func setExperiencesBasedOnTime() {
        experiencesWithinLargerRange = PersistenceController.shared.getExperiences(near: time)
    }


    var body: some View {
        EditIngestionContent(
            ingestion: ingestion,
            roaDose: roaDose,
            customUnit: $selectedCustomUnit,
            otherUnits: filteredCustomUnit,
            route: route,
            selectedTimePickerOption: $selectedTimePickerOption,
            time: $time,
            endTime: $endTime,
            dose: $dose,
            units: $units,
            isEstimate: $isEstimate,
            estimatedDoseStandardDeviation: $estimatedDoseStandardDeviation,
            note: $note,
            consumerName: $consumerName,
            siteSelection: $siteSelection,
            save: { request(.save) },
            onDeleted: { dismiss() },
            deleteWebhookMessage: WebhookManager.shared.deleteMessage,
            timelineVisibility: $timelineVisibility,
            selectedExperience: $selectedExperience,
            wantsToForceNewExperience: $wantsToForceNewExperience,
            experiencesWithinLargerRange: experiencesWithinLargerRange,
            sheetToShow: $sheetToShow
        ) {
            identitySection
            if ingestion.isUnconfirmed { confirmationSection }
        }
        .onFirstAppear {
            locationManager.selectLocation(ingestion.location?.asLocation)
            time = ingestion.timeUnwrapped
            if let eTime = ingestion.endTime {
                endTime = eTime
                selectedTimePickerOption = .timeRange
            } else {
                endTime = time.addingTimeInterval(30*60)
            }
            dose = ingestion.doseUnwrapped
            units = ingestion.unitsUnwrapped
            isEstimate = ingestion.isEstimate
            estimatedDoseStandardDeviation = ingestion.estimatedDoseStandardDeviationUnwrapped
            note = ingestion.noteUnwrapped
            timelineVisibility = ingestion.timelineVisibility
            consumerName = ingestion.consumerName ?? ""
            selectedCustomUnit = ingestion.customUnit
            selectedExperience = ingestion.experience
            siteSelection = AdministrationSiteSelection(
                route: ingestion.administrationRouteUnwrapped,
                storedSite: ingestion.administrationSiteUnwrapped
            )
            setExperiencesBasedOnTime()
        }
        .onChange(of: time) { _ in
            setExperiencesBasedOnTime()
        }
        .confirmationDialog("Save Correction?", isPresented: Binding(
            get: { correctionRequest != nil },
            set: { if !$0 { correctionRequest = nil } }
        ), titleVisibility: .visible, presenting: correctionRequest) { request in
            Button(ingestion.stockChange != nil ? "Keep Stock History" : "Save Correction") {
                save(request)
            }
            if ingestion.stockChange?.canReverseUse == true {
                Button("Save and Return Stock") { save(request, returningStock: true) }
            }
        } message: { _ in
            Text(correctionImpact.joined(separator: "\n"))
        }
        .sheet(item: $sheetToShow, content: { sheet in
            switch sheet {
            case .editLocation:
                ChooseLocationScreen(
                    locationManager: locationManager,
                    initialLocation: locationManager.selectedLocation,
                    onDone: locationManager.selectLocation
                )
            case .editConsumer:
                EditConsumerScreen(consumerName: $consumerName)
            case .correctSubstance:
                NavigationStack {
                    SubstancePickerList { $0 }
                        .navigationDestination(for: AddIngestionSubstance.self) { candidate in
                            List {
                                Button("Use \(candidate.displayName)") {
                                    correctedSubstance = candidate
                                    updateIdentity()
                                    sheetToShow = nil
                                }
                            }
                            .navigationTitle(candidate.displayName)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { sheetToShow = nil }
                            }
                        }
                }
            }
        })
    }

    private var correctionImpact: [String] {
        guard correctsIdentity || splitsBatch else { return [] }
        var impact: [String] = []
        if ingestion.pendingConfirmationEntries.count > 1 {
            impact.append(String(localized: "The unconfirmed batch will be detached from its product and routine"))
        }
        if ingestion.stockChange != nil {
            impact.append(String(localized: "The corrected entry will be detached from its stock use"))
        }
        if ingestion.routineOccurrence != nil {
            impact.append(String(localized: "The corrected entry will be detached from its routine occurrence"))
        }
        if ingestion.formulation != nil {
            impact.append(String(localized: "The corrected entry will be detached from its formulation"))
        }
        return impact
    }

    private var identitySection: some View {
        Section {
            Button {
                sheetToShow = .correctSubstance
            } label: {
                LabeledContent("Change Substance", value: PersistenceController.shared.displayName(for: substanceName))
            }
            Picker("Route", selection: Binding(
                get: { route },
                set: {
                    correctedRoute = $0
                    updateIdentity()
                }
            )) {
                ForEach(AdministrationRoute.allCases) { route in
                    Text(route.rawValue.localizedCapitalized).tag(route)
                }
            }
        } header: {
            Text("Substance")
        } footer: {
            if correctsIdentity {
                Text("Check the amount and units again before saving.")
            }
        }
    }

    private var movesExperience: Bool {
        wantsToForceNewExperience || selectedExperience?.objectID != ingestion.experience?.objectID
    }

    private var splitsBatch: Bool { movesExperience && ingestion.pendingConfirmationEntries.count > 1 }

    private var confirmationInventoryUse: Inventory.Use? {
        guard ingestion.isUnconfirmed, !correctsIdentity, !movesExperience else { return nil }
        let arguments = ingestion.pendingConfirmationEntries.map { entry in
            guard entry.objectID == ingestion.objectID else { return entry.inventoryArguments }
            return FinishIngestionScreenArguments(
                substanceName: substanceName, administrationRoute: route, dose: dose,
                units: selectedCustomUnit?.unitUnwrapped ?? units,
                isEstimate: isEstimate, estimatedDoseStandardDeviation: estimatedDoseStandardDeviation,
                customUnit: selectedCustomUnit, formulation: entry.formulation, formulationAmount: entry.formulationAmount
            )
        }
        return Inventory.Use(arguments)
    }

    @ViewBuilder
    private var confirmationSection: some View {
        let count = movesExperience ? 1 : ingestion.pendingConfirmationEntries.count
        Section {
            Button(count > 1 ? "Confirm \(count) Ingestions" : "Confirm Ingestion") {
                request(.confirm)
            }
            if !webhookPresets.isEmpty {
                Toggle("Send Webhooks on Confirmation", isOn: $sendConfirmationWebhooks)
                if sendConfirmationWebhooks {
                    LabeledContent("Recipients", value: webhookPresets.map(\.displayName).formatted(.list(type: .and)))
                }
            }
        } header: {
            Text("Unconfirmed")
        } footer: {
            Text("Confirmation includes these entries in totals and keeps their recorded times.")
        }
        if let confirmationInventoryUse {
            InventorySourcePicker(use: confirmationInventoryUse, selection: $stockContainerID)
        }
    }

    private func updateIdentity() {
        selectedCustomUnit = correctsIdentity ? nil : ingestion.customUnit
        units = correctedSubstance?.customSubstanceUnits ?? roaDose?.units ?? (correctsIdentity ? "" : ingestion.unitsUnwrapped)
        dose = correctsIdentity ? nil : ingestion.doseUnwrapped
        isEstimate = !correctsIdentity && ingestion.isEstimate
        estimatedDoseStandardDeviation = correctsIdentity ? nil : ingestion.estimatedDoseStandardDeviationUnwrapped
        siteSelection = AdministrationSiteSelection(route: route, storedSite: correctsIdentity ? "" : ingestion.administrationSiteUnwrapped)
        stockContainerID = nil
    }

    private func request(_ request: EditRequest) {
        if correctionImpact.isEmpty {
            save(request)
        } else {
            correctionRequest = request
        }
    }

    private func save(_ request: EditRequest, returningStock: Bool = false) {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let ingestion = try PersistenceController.journalObject(self.ingestion, in: context)
            let saved = try PersistenceController.withJournalStoreWrite {
                try stageEdits(to: ingestion, returningStock: returningStock, in: context)
                let saved = try request == .confirm
                    ? IngestionSaving.stageConfirmation(for: ingestion, stockContainerID: confirmationInventoryUse == nil ? nil : stockContainerID, in: context)
                    : [ingestion]
                try PersistenceController.saveJournalChanges(in: context)
                return saved
            }
            let confirmed = request == .confirm ? saved : []
            let recipients = sendConfirmationWebhooks ? webhookPresets.map(\.objectID) : []
            IngestionSaving.didSave(saved, newIngestions: confirmed, sendingWebhooksTo: recipients)
            dismiss()
        } catch {
            toastViewModel.showErrorToast(message: (error as? LocalizedError)?.errorDescription ?? "Failed to save ingestion")
        }
    }

    private func stageEdits(to ingestion: Ingestion, returningStock: Bool, in context: NSManagedObjectContext) throws {
        if correctsIdentity || splitsBatch {
            for member in ingestion.pendingConfirmationEntries where member != ingestion {
                member.routineOccurrence = nil
                member.formulation = nil
                member.formulationAmount = 0
            }
        }
        if correctsIdentity {
            if returningStock { try Inventory.stageUsageReversal(for: ingestion) }
            ingestion.stockChange = nil
            ingestion.routineOccurrence = nil
            ingestion.formulation = nil
            ingestion.formulationAmount = 0
            if ingestion.substanceNameUnwrapped != substanceName {
                let request = SubstanceCompanion.fetchRequest()
                request.predicate = NSPredicate(format: "substanceName == %@", substanceName)
                request.fetchLimit = 1
                let existing = try context.fetch(request).first
                let companion = existing ?? SubstanceCompanion(context: context)
                if existing == nil {
                    companion.substanceName = substanceName
                    companion.colorAsText = SubstanceColor.suggested(
                        avoiding: PersistenceController.shared.getSubstanceCompanions().map(\.color)
                    ).rawValue
                }
                ingestion.substanceCompanion = companion
                ingestion.color = companion.colorAsText
            }
            ingestion.substanceName = substanceName
            ingestion.administrationRoute = route.rawValue
        }
        if splitsBatch {
            ingestion.routineOccurrence = nil
            ingestion.formulation = nil
            ingestion.formulationAmount = 0
            ingestion.confirmationBatchID = nil
        }
        ingestion.time = time
        if selectedTimePickerOption == .timeRange {
            ingestion.endTime = endTime
        } else {
            ingestion.endTime = nil
        }
        ingestion.dose = dose ?? 0
        if let selectedCustomUnit {
            ingestion.customUnit = try PersistenceController.journalObject(selectedCustomUnit, in: context)
            ingestion.units = selectedCustomUnit.unitUnwrapped
        } else {
            ingestion.units = units
            ingestion.customUnit = nil
        }
        ingestion.isEstimate = isEstimate
        ingestion.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation ?? 0
        ingestion.note = note
        ingestion.timelineVisibility = timelineVisibility
        ingestion.consumerName = Ingestion.storedConsumerName(consumerName)
        let site = siteSelection.siteString(for: ingestion.administrationRouteUnwrapped)
        ingestion.administrationSite = site.isEmpty ? nil : site

        ingestion.setLocation(locationManager.selectedLocation)

        if wantsToForceNewExperience || selectedExperience == nil {
            ingestion.experience = Experience.create(at: time, in: context)
        } else {
            ingestion.experience = try selectedExperience.map { try PersistenceController.journalObject($0, in: context) }
        }
    }


}

// MARK: - EditIngestionContent

struct EditIngestionContent<HeaderContent: View>: View {
    @ObservedObject var ingestion: Ingestion
    let roaDose: RoaDose?
    @Binding var customUnit: CustomUnit?
    let otherUnits: [CustomUnit]
    let route: AdministrationRoute
    @Binding var selectedTimePickerOption: TimePickerOption
    @Binding var time: Date
    @Binding var endTime: Date
    @Binding var dose: Double?
    @Binding var units: String
    @Binding var isEstimate: Bool
    @Binding var estimatedDoseStandardDeviation: Double?
    @Binding var note: String
    @Binding var consumerName: String
    @Binding var siteSelection: AdministrationSiteSelection
    let save: () -> Void
    let onDeleted: () -> Void
    let deleteWebhookMessage: (WebhookMessage) async -> Bool
    @Binding var timelineVisibility: Ingestion.TimelineVisibility
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiencesWithinLargerRange: [Experience]
    @Binding var sheetToShow: EditIngestionScreen.SheetOption?
    @ViewBuilder var headerContent: HeaderContent

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @State private var deletionRequest: IngestionDeletion.Request?

    var body: some View {
        NavigationStack {
            Form {
                headerContent
                Section("\(route.rawValue.localizedCapitalized) Dose") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let roaDose {
                            RoaDoseRow(roaDose: roaDose)
                        }
                        if let customUnit {
                            CustomUnitCalculationText(
                                customUnit: customUnit,
                                dose: dose,
                                isEstimate: isEstimate,
                                estimatedDoseStandardDeviation: estimatedDoseStandardDeviation)
                        } else {
                            DosePicker(
                                roaDose: roaDose,
                                doseMaybe: $dose,
                                selectedUnits: $units)
                            EstimateFields(
                                isEstimate: $isEstimate,
                                standardDeviation: $estimatedDoseStandardDeviation,
                                units: units
                            )
                        }
                    }
                    if !otherUnits.isEmpty {
                        NavigationLink {
                            ChooseCustomUnitScreen(customUnit: $customUnit, customUnits: otherUnits)
                        } label: {
                            HStack {
                                Text("Choose Unit")
                                Spacer()
                                Group {
                                    if let customUnit {
                                        Text(customUnit.nameUnwrapped)
                                    } else {
                                        Text("Default")
                                    }
                                }.foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: customUnit, perform: { unit in
                            units = unit?.unit ?? roaDose?.units ?? ""
                        })
                    }
                }.listRowSeparator(.hidden)
                if let customUnit {
                    Section {
                        CustomUnitDosePicker(
                            customUnit: customUnit,
                            dose: $dose,
                            isEstimate: $isEstimate,
                            estimatedDoseStandardDeviation: $estimatedDoseStandardDeviation)
                    } header: {
                        Text(customUnit.nameUnwrapped)
                    } footer: {
                        if !customUnit.noteUnwrapped.isEmpty {
                            Text(customUnit.noteUnwrapped)
                        }
                    }.listRowSeparator(.hidden)
                }
                Section("Notes") {
                    TextField("Enter Note", text: $note, axis: .vertical)
                        .autocapitalization(.sentences)
                }
                Section {
                    TimePointOrRangePicker(
                        selectedTimePickerOption: $selectedTimePickerOption,
                        selectedTime: $time,
                        selectedEndTime: $endTime
                    )
                    ExperiencePickerRow(
                        selectedExperience: $selectedExperience,
                        wantsToForceNewExperience: $wantsToForceNewExperience,
                        experiences: experiencesWithinLargerRange
                    )
                    ConsumerRow(consumerName: consumerName) { sheetToShow = .editConsumer }
                    AdministrationSitePicker(route: route, selection: $siteSelection)
                    LocationButton(locationName: locationManager.selectedLocation?.name) { sheetToShow = .editLocation }
                }.listRowSeparator(.hidden)
                if let stockChange = ingestion.stockChange, let container = stockChange.container {
                    Section {
                        NavigationLink {
                            StockContainerDetail(container: container)
                        } label: {
                            LabeledContent("Container", value: container.displayName)
                        }
                        LabeledContent("Recorded Stock Use", value: container.quantityLabel(-stockChange.quantity))
                    } header: {
                        Text("Inventory")
                    } footer: {
                        Text("To change the amount used from stock, correct the container’s count.")
                    }
                }
                Section {
                    Picker("Timeline", selection: $timelineVisibility) {
                        Text("Substance Default").tag(Ingestion.TimelineVisibility.substanceDefault)
                        Text("Show").tag(Ingestion.TimelineVisibility.show)
                        Text("Hide").tag(Ingestion.TimelineVisibility.hide)
                    }
                    Button(action: {
                        dismiss()
                        addIngestionAtSameTime()
                    }) {
                        Label("Add ingestion at same time", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        requestIngestionDeletion(ingestion, confirmation: $deletionRequest, onDeleted: onDeleted)
                    } label: {
                        Label("Delete Ingestion", systemImage: "trash")
                    }
                }
                if !ingestion.webhookMessagesSorted.isEmpty {
                    Section("Sent Webhooks") {
                        ForEach(ingestion.webhookMessagesSorted, id: \.objectID) { message in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(message.presetNameUnwrapped)
                                    if let date = message.creationDate {
                                        Text(date, style: .time)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        _ = await deleteWebhookMessage(message)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save, label: {
                        Text("Save")
                    })
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {dismiss()}, label: {
                        Text("Cancel")
                    })
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Ingestion")
            .confirmIngestionDeletion($deletionRequest, onDeleted: onDeleted)
        }
    }

    private func addIngestionAtSameTime() {
        Navigator.shared.showAddIngestionFullScreenCover(
            startingAt: time, endingAt: selectedTimePickerOption == .timeRange ? endTime : nil
        )
    }
}

#Preview("Edit regular ingestion") {
    EditIngestionContent(
        ingestion: Ingestion.knownDosePreviewSample,
        roaDose: SubstanceRepo.shared.getSubstance(name: "MDMA")!.getDose(for: .oral)!,
        customUnit: .constant(nil),
        otherUnits: [
            CustomUnit.previewSample
        ],
        route: .oral,
        selectedTimePickerOption: .constant(.pointInTime),
        time: .constant(Date()),
        endTime: .constant(Date()),
        dose: .constant(50),
        units: .constant("mg"),
        isEstimate: .constant(false),
        estimatedDoseStandardDeviation: .constant(nil),
        note: .constant("These are my notes"),
        consumerName: .constant("Marc"),
        siteSelection: .constant(AdministrationSiteSelection()),
        save: { },
        onDeleted: { },
        deleteWebhookMessage: { _ in return true },
        timelineVisibility: .constant(.substanceDefault),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [],
        sheetToShow: .constant(nil)
    ) { EmptyView() }.environmentObject(LocationManager())
}

#Preview("Edit custom unit ingestion") {
    EditIngestionContent(
        ingestion: Ingestion.customUnitPreviewSample,
        roaDose: SubstanceRepo.shared.getSubstance(name: "Ketamine")!.getDose(for: .oral)!,
        customUnit: .constant(CustomUnit.previewSample),
        otherUnits: [],
        route: .oral,
        selectedTimePickerOption: .constant(.pointInTime),
        time: .constant(Date()),
        endTime: .constant(Date()),
        dose: .constant(2),
        units: .constant("mg"),
        isEstimate: .constant(false),
        estimatedDoseStandardDeviation: .constant(nil),
        note: .constant("These are my notes"),
        consumerName: .constant("Marc"),
        siteSelection: .constant(AdministrationSiteSelection()),
        save: { },
        onDeleted: { },
        deleteWebhookMessage: { _ in return true },
        timelineVisibility: .constant(.substanceDefault),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [],
        sheetToShow: .constant(nil)
    ) { EmptyView() }.environmentObject(LocationManager())
}

