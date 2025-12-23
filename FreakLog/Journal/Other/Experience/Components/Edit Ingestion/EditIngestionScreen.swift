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
    @State private var stomachFullness = StomachFullness.empty
    @State private var selectedCustomUnit: CustomUnit? = nil
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var selectedNostril: Nostril?
    @State private var selectedVein: Vein?
    @State private var selectedMuscle: Muscle?
    @State private var selectedSubQSite: SubcutaneousSite?

    @AppStorage(PersistenceConfiguration.Keys.isEyeOpenKey2) var isEyeOpen: Bool = false

    @Environment(\.dismiss) var dismiss

    @FetchRequest(
        sortDescriptors: []
    ) var customUnits: FetchedResults<CustomUnit>

    private var filteredCustomUnit: [CustomUnit] {
        customUnits.filter { unit in
            unit.substanceNameUnwrapped == ingestion.substanceNameUnwrapped && unit.administrationRouteUnwrapped == ingestion.administrationRouteUnwrapped
        }
    }

    private var roaDose: RoaDose? {
        ingestion.substance?.getDose(for: ingestion.administrationRouteUnwrapped)
    }

    @State private var experiencesWithinLargerRange: [Experience] = []
    @State private var wantsToForceNewExperience = false
    @State private var selectedExperience: Experience?
    @State private var hasWebhookMessageState: Bool = false

    func setExperiencesBasedOnTime() {
        let fetchRequest = Experience.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        fetchRequest.predicate = FinishIngestionScreen.getPredicate(from: time)
        experiencesWithinLargerRange = (try? PersistenceController.shared.viewContext.fetch(fetchRequest)) ?? []
    }


    var body: some View {
        EditIngestionContent(
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
            stomachFullness: $stomachFullness,
            consumerName: $consumerName,
            selectedNostril: $selectedNostril,
            selectedVein: $selectedVein,
            selectedMuscle: $selectedMuscle,
            selectedSubQSite: $selectedSubQSite,
            save: save,
            delete: delete,
            deleteWebhookMessage: deleteWebhookMessage,
            hasWebhookMessage: $hasWebhookMessageState,
            isEyeOpen: isEyeOpen,
            isHidden: $isHidden,
            selectedExperience: $selectedExperience,
            wantsToForceNewExperience: $wantsToForceNewExperience,
            experiencesWithinLargerRange: experiencesWithinLargerRange
        ).onFirstAppear {
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
            if let fullness = ingestion.stomachFullnessUnwrapped {
                stomachFullness = fullness
            }
            let site = ingestion.administrationSiteUnwrapped
            if !site.isEmpty {
                switch ingestion.administrationRouteUnwrapped {
                case .insufflated:
                    selectedNostril = Nostril(rawValue: site)
                case .intravenous:
                    selectedVein = Vein(rawValue: site)
                case .intramuscular:
                    selectedMuscle = Muscle(rawValue: site)
                case .subcutaneous:
                    selectedSubQSite = SubcutaneousSite(rawValue: site)
                default:
                    break
                }
            }
            setExperiencesBasedOnTime()
            hasWebhookMessageState = !ingestion.webhookMessageIdUnwrapped.isEmpty
        }
        .onChange(of: time) { _ in
            setExperiencesBasedOnTime()
        }
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
        if ingestion.administrationRouteUnwrapped == .oral {
            ingestion.stomachFullness = stomachFullness.rawValue
        }
        let siteString = getSiteString()
        if !siteString.isEmpty {
            ingestion.administrationSite = siteString
        } else {
            ingestion.administrationSite = nil
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
        Task {
            await FinishIngestionScreen.editWebhookMessageIfNeeded(for: ingestion)
        }
        ingestion.experience?.objectWillChange.send()
        dismiss()
    }

    private func delete() {
        let webhookMessageId = ingestion.webhookMessageIdUnwrapped
        Task {
            await FinishIngestionScreen.deleteWebhookMessage(messageId: webhookMessageId)
        }
        PersistenceController.shared.viewContext.delete(ingestion)
        PersistenceController.shared.saveViewContext()
        dismiss()
    }

    private func deleteWebhookMessage() async -> Bool {
        let webhookMessageId = ingestion.webhookMessageIdUnwrapped
        let success = await FinishIngestionScreen.deleteWebhookMessage(messageId: webhookMessageId)
        if success {
            ingestion.webhookMessageId = nil
            hasWebhookMessageState = false
            PersistenceController.shared.saveViewContext()
        }
        return success
    }

    private func getSiteString() -> String {
        if ingestion.administrationRouteUnwrapped == .insufflated, let val = selectedNostril {
            return val.rawValue
        } else if ingestion.administrationRouteUnwrapped == .intravenous, let val = selectedVein {
            return val.rawValue
        } else if ingestion.administrationRouteUnwrapped == .intramuscular, let val = selectedMuscle {
            return val.rawValue
        } else if ingestion.administrationRouteUnwrapped == .subcutaneous, let val = selectedSubQSite {
            return val.rawValue
        }
        return ""
    }
}

// MARK: - EditIngestionContent

struct EditIngestionContent: View {
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
    @Binding var stomachFullness: StomachFullness
    @Binding var consumerName: String
    @Binding var selectedNostril: Nostril?
    @Binding var selectedVein: Vein?
    @Binding var selectedMuscle: Muscle?
    @Binding var selectedSubQSite: SubcutaneousSite?
    let save: () -> Void
    let delete: () -> Void
    let deleteWebhookMessage: () async -> Bool
    @Binding var hasWebhookMessage: Bool
    let isEyeOpen: Bool
    @Binding var isHidden: Bool
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiencesWithinLargerRange: [Experience]

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
                            isConsumerSheetPresented.toggle()
                        } label: {
                            let displayedName = areYouConsumer ? "You" : consumerName
                            Label(displayedName, systemImage: "person")
                        }
                    }
                    if route == .oral, isEyeOpen {
                        StomachFullnessPicker(stomachFullness: $stomachFullness)
                            .pickerStyle(.menu)
                    }
                    if route == .insufflated {
                        NostrilPicker(selection: $selectedNostril)
                            .pickerStyle(.menu)
                    }
                    if route == .intravenous {
                        VeinPicker(selection: $selectedVein)
                            .pickerStyle(.menu)
                    }
                    if route == .intramuscular {
                        MusclePicker(selection: $selectedMuscle)
                            .pickerStyle(.menu)
                    }
                    if route == .subcutaneous {
                        SubQSitePicker(selection: $selectedSubQSite)
                            .pickerStyle(.menu)
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
                    if hasWebhookMessage {
                        Button(action: {
                            Task {
                                let success = await deleteWebhookMessage()
                                if success {
                                    hasWebhookMessage = false
                                }
                            }
                        }) {
                            Label("Delete Webhook Message", systemImage: "trash").foregroundColor(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $isConsumerSheetPresented, content: {
                EditConsumerScreen(consumerName: $consumerName)
            })
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
        UserDefaults.standard.set(time.timeIntervalSince1970, forKey: PersistenceConfiguration.Keys.clonedIngestionTime)
        Navigator.shared.showAddIngestionFullScreenCover()
    }

    @State private var isConsumerSheetPresented = false

    private var areYouConsumer: Bool {
        consumerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

}

#Preview("Edit regular ingestion") {
    EditIngestionContent(
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
        stomachFullness: .constant(.full),
        consumerName: .constant("Marc"),
        selectedNostril: .constant(nil),
        selectedVein: .constant(nil),
        selectedMuscle: .constant(nil),
        selectedSubQSite: .constant(nil),
        save: { },
        delete: { },
        deleteWebhookMessage: { return true },
        hasWebhookMessage: .constant(false),
        isEyeOpen: true,
        isHidden: .constant(false),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: []
    )
}

#Preview("Edit custom unit ingestion") {
    EditIngestionContent(
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
        stomachFullness: .constant(.full),
        consumerName: .constant("Marc"),
        selectedNostril: .constant(nil),
        selectedVein: .constant(nil),
        selectedMuscle: .constant(nil),
        selectedSubQSite: .constant(nil),
        save: { },
        delete: { },
        deleteWebhookMessage: { return true },
        hasWebhookMessage: .constant(false),
        isEyeOpen: true,
        isHidden: .constant(false),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [])
}

