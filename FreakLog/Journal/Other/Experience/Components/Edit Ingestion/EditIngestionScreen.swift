import SwiftUI

// MARK: - EditIngestionScreen

struct EditIngestionScreen: View {
    let ingestion: Ingestion
    @Binding var isHidden: Bool
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

    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var locationManager: LocationManager

    @State private var sheetToShow: SheetOption?

    enum SheetOption: Identifiable {
        case editLocation
        case editConsumer

        var id: Self {
            self
        }
    }

    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    var customUnits: FetchedResults<CustomUnit>

    private var filteredCustomUnit: [CustomUnit] {
        customUnits.filter { unit in
            unit.substanceNameUnwrapped == ingestion.substanceNameUnwrapped && unit.administrationRouteUnwrapped == ingestion.administrationRouteUnwrapped
        }
    }

    private var roaDose: RoaDose? {
        ingestion.roaDose
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
            substanceName: ingestion.substanceNameUnwrapped,
            roaDose: roaDose,
            customUnit: $selectedCustomUnit,
            otherUnits: filteredCustomUnit,
            route: ingestion.administrationRouteUnwrapped,
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
            save: save,
            delete: delete,
            deleteWebhookMessage: deleteWebhookMessage,
            isEyeOpen: isEyeOpen,
            isHidden: $isHidden,
            selectedExperience: $selectedExperience,
            wantsToForceNewExperience: $wantsToForceNewExperience,
            experiencesWithinLargerRange: experiencesWithinLargerRange,
            sheetToShow: $sheetToShow
        ).onFirstAppear {
            if let loc = ingestion.location {
                locationManager.selectedLocation = Location(name: loc.nameUnwrapped, longitude: loc.longitudeUnwrapped, latitude: loc.latitudeUnwrapped)
                locationManager.selectedLocationName = loc.nameUnwrapped
            }
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
        .sheet(item: $sheetToShow, content: { sheet in
            switch sheet {
            case .editLocation:
                ChooseLocationScreen(locationManager: locationManager, onDone: { })
            case .editConsumer:
                EditConsumerScreen(consumerName: $consumerName)
            }
        })
    }

    private func save() {
        ingestion.time = time
        if selectedTimePickerOption == .timeRange {
            ingestion.endTime = endTime
        } else {
            ingestion.endTime = nil
        }
        ingestion.dose = dose ?? 0
        if let selectedCustomUnit {
            ingestion.customUnit?.removeFromIngestions(ingestion)
            ingestion.customUnit = selectedCustomUnit
            ingestion.units = selectedCustomUnit.unitUnwrapped
        } else {
            ingestion.units = roaDose?.units ?? units
            ingestion.customUnit?.removeFromIngestions(ingestion)
        }
        ingestion.isEstimate = isEstimate
        ingestion.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation ?? 0
        ingestion.note = note
        if consumerName.trimmingCharacters(in: .whitespaces).isEmpty {
            ingestion.consumerName = nil
        } else {
            ingestion.consumerName = consumerName
        }
        let site = siteSelection.siteString(for: ingestion.administrationRouteUnwrapped)
        ingestion.administrationSite = site.isEmpty ? nil : site

        if let selectedLocation = locationManager.selectedLocation {
            if let existingLocation = ingestion.location {
                existingLocation.name = selectedLocation.name
                existingLocation.latitude = selectedLocation.latitude ?? 0
                existingLocation.longitude = selectedLocation.longitude ?? 0
            } else {
                let newLocation = ExperienceLocation(context: PersistenceController.shared.viewContext)
                newLocation.name = selectedLocation.name
                newLocation.latitude = selectedLocation.latitude ?? 0
                newLocation.longitude = selectedLocation.longitude ?? 0
                ingestion.location = newLocation
            }
        } else {
            if let existingLocation = ingestion.location {
                PersistenceController.shared.viewContext.delete(existingLocation)
                ingestion.location = nil
            }
        }

        if wantsToForceNewExperience || selectedExperience == nil {
            let context = PersistenceController.shared.viewContext
            let newExperience = Experience(context: context)
            newExperience.creationDate = Date()
            newExperience.sortDate = time
            newExperience.title = time.asDateString
            newExperience.text = ""
            ingestion.experience = newExperience
        } else {
            ingestion.experience = selectedExperience
        }
        PersistenceController.shared.saveViewContext()
        ingestion.experience?.objectWillChange.send()
        Task {
            await WebhookManager.shared.editWebhookMessages(for: ingestion)
        }
        dismiss()
    }

    private func delete() {
        Task {
            await IngestionDeletion.delete(ingestions: [ingestion])
            dismiss()
        }
    }

    private func deleteWebhookMessage(_ message: WebhookMessage) async -> Bool {
        guard let preset = message.webhookPreset,
              let messageId = message.messageId else {
            return false
        }

        let success = await WebhookService.deleteWebhookMessage(for: preset, messageId: messageId)
        if success {
            let context = PersistenceController.shared.viewContext
            context.delete(message)
            PersistenceController.shared.saveViewContext()
        }
        return success
    }

}

// MARK: - EditIngestionContent

struct EditIngestionContent: View {
    @ObservedObject var ingestion: Ingestion
    let substanceName: String
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
    let delete: () -> Void
    let deleteWebhookMessage: (WebhookMessage) async -> Bool
    let isEyeOpen: Bool
    @Binding var isHidden: Bool
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiencesWithinLargerRange: [Experience]
    @Binding var sheetToShow: EditIngestionScreen.SheetOption?

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                            Toggle("Estimate", isOn: $isEstimate)
                                .tint(.accentColor)
                            if isEstimate {
                                HStack {
                                    Image(systemName: "plusminus")
                                    TextField(
                                        "Estimated standard deviation",
                                        value: $estimatedDoseStandardDeviation,
                                        format: .number
                                    )
                                    .keyboardType(.decimalPad)
                                    Spacer()
                                    Text(units)
                                }
                            }
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
                    if experiencesWithinLargerRange.count > 0 {
                        NavigationLink {
                            ExperiencePickerScreen(
                                selectedExperience: $selectedExperience,
                                wantsToForceNewExperience: $wantsToForceNewExperience,
                                experiences: experiencesWithinLargerRange)
                        } label: {
                            HStack {
                                Text("Experience")
                                Spacer()
                                if let exp = selectedExperience {
                                    Text(exp.titleUnwrapped)
                                } else {
                                    Text("New Experience")
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Consumer")
                        Spacer()
                        Button {
                            sheetToShow = .editConsumer
                        } label: {
                            let displayedName = areYouConsumer ? "You" : consumerName
                            Label(displayedName, systemImage: "person")
                        }
                    }
                    AdministrationSitePicker(route: route, selection: $siteSelection)
                    Button {
                        sheetToShow = .editLocation
                    } label: {
                        if let locationName = locationManager.selectedLocation?.name {
                            Label(locationName, systemImage: "mappin")
                        } else {
                            Label("Add Location", systemImage: "plus")
                        }
                    }
                }.listRowSeparator(.hidden)
                Section {
                    Toggle("Hide in timeline", isOn: $isHidden).tint(.accentColor)
                    Button(action: {
                        dismiss()
                        addIngestionAtSameTime()
                    }) {
                        Label("Add ingestion at same time", systemImage: "plus")
                    }
                    Button(action: delete) {
                        Label("Delete ingestion", systemImage: "trash").foregroundColor(.red)
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
        }
    }

    private func addIngestionAtSameTime() {
        UserDefaults.standard.set(time.timeIntervalSince1970, forKey: PersistenceController.clonedIngestionTimeKey)
        Navigator.shared.showAddIngestionFullScreenCover()
    }

    private var areYouConsumer: Bool {
        consumerName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

#Preview("Edit regular ingestion") {
    EditIngestionContent(
        ingestion: Ingestion.knownDosePreviewSample,
        substanceName: "MDMA",
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
        delete: { },
        deleteWebhookMessage: { _ in return true },
        isEyeOpen: true,
        isHidden: .constant(false),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [],
        sheetToShow: .constant(nil)
    ).environmentObject(LocationManager())
}

#Preview("Edit custom unit ingestion") {
    EditIngestionContent(
        ingestion: Ingestion.customUnitPreviewSample,
        substanceName: "Ketamine",
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
        delete: { },
        deleteWebhookMessage: { _ in return true },
        isEyeOpen: true,
        isHidden: .constant(false),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [],
        sheetToShow: .constant(nil)
    ).environmentObject(LocationManager())
}

