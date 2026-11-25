import CoreData
import SwiftUI

// MARK: - EditIngestionScreen

struct EditIngestionScreen: View {
    let ingestion: Ingestion
    @State private var isHidden = false
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

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var toastViewModel: ToastViewModel

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
            deleteWebhookMessage: WebhookManager.shared.deleteMessage,
            isHidden: $isHidden,
            selectedExperience: $selectedExperience,
            wantsToForceNewExperience: $wantsToForceNewExperience,
            experiencesWithinLargerRange: experiencesWithinLargerRange,
            sheetToShow: $sheetToShow
        ).onFirstAppear {
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
            isHidden = ingestion.isHiddenInTimeline
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
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let ingestion = try PersistenceController.journalObject(self.ingestion, in: context)
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
                ingestion.units = roaDose?.units ?? units
                ingestion.customUnit = nil
            }
            ingestion.isEstimate = isEstimate
            ingestion.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation ?? 0
            ingestion.note = note
            ingestion.isHiddenInTimeline = isHidden
            ingestion.consumerName = Ingestion.storedConsumerName(consumerName)
            let site = siteSelection.siteString(for: ingestion.administrationRouteUnwrapped)
            ingestion.administrationSite = site.isEmpty ? nil : site

            ingestion.setLocation(locationManager.selectedLocation)

            if wantsToForceNewExperience || selectedExperience == nil {
                ingestion.experience = Experience.create(at: time, in: context)
            } else {
                ingestion.experience = try selectedExperience.map { try PersistenceController.journalObject($0, in: context) }
            }
            try IngestionSaving.save(ingestion)
            dismiss()
        } catch {
            toastViewModel.showErrorToast(message: "Failed to save ingestion")
        }
    }

    private func delete(returningStock: Bool) {
        Task {
            if await IngestionDeletion.delete(ingestions: [ingestion], returningStock: returningStock) {
                dismiss()
            }
        }
    }
}

// MARK: - EditIngestionContent

struct EditIngestionContent: View {
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
    let delete: (Bool) -> Void
    let deleteWebhookMessage: (WebhookMessage) async -> Bool
    @Binding var isHidden: Bool
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiencesWithinLargerRange: [Experience]
    @Binding var sheetToShow: EditIngestionScreen.SheetOption?

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @State private var confirmsDeletionWithStock = false

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
                    Toggle("Hide in timeline", isOn: $isHidden).tint(.accentColor)
                    Button(action: {
                        dismiss()
                        addIngestionAtSameTime()
                    }) {
                        Label("Add ingestion at same time", systemImage: "plus")
                    }
                    Button {
                        if ingestion.stockChange == nil {
                            delete(false)
                        } else {
                            confirmsDeletionWithStock = true
                        }
                    } label: {
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
            .confirmationDialog("Delete Ingestion?", isPresented: $confirmsDeletionWithStock, titleVisibility: .visible) {
                Button("Delete Entry, Keep Stock Use", role: .destructive) { delete(false) }
                if ingestion.stockChange?.canReverseUse == true {
                    Button("Delete Entry and Return Stock", role: .destructive) { delete(true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if ingestion.stockChange?.canReverseUse == true {
                    Text("Return the stock if this entry was logged by mistake.")
                } else {
                    Text("The container’s stock history will still show the original amount used.")
                }
            }
        }
    }

    private func addIngestionAtSameTime() {
        Navigator.shared.showAddIngestionFullScreenCover(startingAt: time)
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
        delete: { _ in },
        deleteWebhookMessage: { _ in return true },
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
        delete: { _ in },
        deleteWebhookMessage: { _ in return true },
        isHidden: .constant(false),
        selectedExperience: .constant(nil),
        wantsToForceNewExperience: .constant(false),
        experiencesWithinLargerRange: [],
        sheetToShow: .constant(nil)
    ).environmentObject(LocationManager())
}

