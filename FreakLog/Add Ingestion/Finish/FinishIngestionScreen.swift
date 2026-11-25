@preconcurrency import CoreData //FIXME
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

struct FinishIngestionScreen: View {
    struct RoutineDraft: Hashable {
        let schedule: RoutineSchedule
        let productID: NSManagedObjectID
    }

    enum SheetOption: Identifiable, Hashable {
        case editTitle
        case editLocation
        case editConsumer
        case setUpRoutine(RoutineDraft)

        var id: Self {
            self
        }
    }

    // Logged together with the same time, experience, consumer, location and note,
    // like the substances of a formulation
    let ingestions: [FinishIngestionScreenArguments]
    let dismiss: () -> Void

    init(arguments: FinishIngestionScreenArguments, dismiss: @escaping () -> Void) {
        self.init(ingestions: [arguments], dismiss: dismiss)
    }

    init(ingestions: [FinishIngestionScreenArguments], dismiss: @escaping () -> Void) {
        self.ingestions = ingestions
        self.dismiss = dismiss
    }

    @EnvironmentObject private var toastViewModel: ToastViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.addIngestionStartTime) private var startTime
    @Environment(\.addIngestionEndTime) private var endTime
    @Environment(\.ingestionPrefillNote) private var prefillNote
    @Environment(\.routineOccurrenceSlot) private var routineSlot
    @State private var sheetToShow: SheetOption?
    @State private var selectedColors: [String: SubstanceColor] = [:]
    @State private var selectedTime = Date()
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var selectedEndTime = Date().addingTimeInterval(30*60)
    @State private var enteredNote = ""
    @State private var showsMoreDetails = false
    @State private var enteredTitle = ""
    @State private var consumerName = ""
    @State private var siteSelection = AdministrationSiteSelection()
    @State private var usedColors = [SubstanceColor]()
    @State private var foundCompanions: [String: SubstanceCompanion] = [:]

    @State private var experiencesWithinLargerRange: [Experience] = []
    @State private var selectedExperience: Experience?
    @State private var wantsToForceNewExperience = false
    @State private var hasSelectedExperience = false
    @State private var saveError: String?
    @State private var isSettingUpLoggedRoutine = false
    @State private var stockContainerID: NSManagedObjectID?
    @State private var wantsToStartLiveActivity = true
    @State private var isUnconfirmed = false
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity: Bool = true

    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest(), animation: .default)
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    @AppStorage(PersistenceController.sendWebhooksEnabledKey) private var defaultSendWebhooks: Bool = false
    @State private var sendRoutineWebhooks = false
    @State private var selectedWebhookPresetIDs: Set<UUID> = []
    @State private var hasInitializedWebhooks = false

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .primaryAction) {
                doneButton
            }
        }
    }

    var doneButton: some View {
        Button(isUnconfirmed ? "Save Unconfirmed" : "Log", action: save)
            .font(.headline)
            .disabled(isSettingUpLoggedRoutine)
    }

    private func save() {
        save(then: nil)
    }

    private func save(then routine: RoutineDraft?) {
        guard !isSettingUpLoggedRoutine else { return }
        do {
            try addIngestionWithExperience()
            generateSuccessHaptic()
            if let routine {
                isSettingUpLoggedRoutine = true
                sheetToShow = .setUpRoutine(routine)
            } else {
                toastViewModel.showSuccessToast()
                dismiss()
            }
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Your ingestion couldn’t be saved. Your details are still here."
            generateFailedHaptic()
        }
    }

    var screen: some View {
        Form {
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.circle")
                    Button("Try Again", action: save)
                }
            }
            if let routineSlot {
                Section("Routine") {
                    LabeledContent("Scheduled") {
                        Text(routineSlot.scheduledAt, format: .dateTime.month().day().hour().minute())
                    }
                }
            }
            Section("Ingestion") {
                ForEach(ingestions.indices, id: \.self) { index in
                    let ingestion = ingestions[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PersistenceController.shared.displayName(for: ingestion.substanceName))
                            .font(.headline)
                        Text(doseDescription(for: ingestion))
                            .monospacedDigit()
                        Text(ingestion.administrationRoute.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
                Toggle("Unconfirmed", isOn: $isUnconfirmed)
                if isUnconfirmed {
                    Text("Confirm this entry in your journal to include it in totals and use stock or send webhooks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !isUnconfirmed, sendWebhooks.wrappedValue, !enabledWebhookPresets.isEmpty {
                Section {
                    LabeledContent("Webhook Recipients", value: webhookRecipients)
                }
            }
            if !isUnconfirmed, let inventoryUse = Inventory.Use(ingestions) {
                InventorySourcePicker(use: inventoryUse, selection: $stockContainerID)
            }
            if !isUnconfirmed {
                ForEach(substanceNames, id: \.self) { name in
                    StatsGoalLoggingSection(substanceName: name, at: selectedTime)
                }
            }
            Section("When") {
                TimePointOrRangePicker(
                    selectedTimePickerOption: $selectedTimePickerOption,
                    selectedTime: $selectedTime,
                    selectedEndTime: $selectedEndTime,
                    showsPresets: true
                )
            }
            Section("Journal") {
                if experiencesWithinLargerRange.isEmpty {
                    LabeledContent("Experience", value: "New Experience")
                } else {
                    ExperiencePickerRow(
                        selectedExperience: $selectedExperience,
                        wantsToForceNewExperience: $wantsToForceNewExperience,
                        experiences: experiencesWithinLargerRange,
                        onSelection: { hasSelectedExperience = true }
                    )
                }
                if let locationName = locationManager.selectedLocation?.name {
                    LocationButton(locationName: locationName) { sheetToShow = .editLocation }
                }
                if selectedExperience == nil {
                    Button {
                        sheetToShow = .editTitle
                    } label: {
                        if enteredTitle.isEmpty {
                            Label("Add Title", systemImage: "plus")
                        } else {
                            Label(enteredTitle, systemImage: "pencil").lineLimit(1)
                        }
                    }
                    if #available(iOS 16.2, *) {
                        let isTimeRecentOrFuture = selectedTime > Date().addingTimeInterval(-12 * 60 * 60)
                        if !isUnconfirmed, LiveActivities.areAvailable, !ActivityManager.shared.isActivityActive, isTimeRecentOrFuture {
                            Toggle("Start Live Activity", isOn: $wantsToStartLiveActivity).tint(.accentColor)
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("More Details", isExpanded: $showsMoreDetails) {
                    TextField("Enter Note", text: $enteredNote, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                    ConsumerRow(consumerName: consumerName) { sheetToShow = .editConsumer }
                    if let sharedRoute {
                        AdministrationSitePicker(route: sharedRoute, selection: $siteSelection)
                    }
                    if locationManager.selectedLocation == nil {
                        LocationButton(locationName: nil) { sheetToShow = .editLocation }
                    }
                    ForEach(substanceNames, id: \.self) { substanceName in
                        let selectedColor = colorBinding(for: substanceName)
                        NavigationLink {
                            ColorPickerScreen(selectedColor: selectedColor, usedColors: usedColors)
                        } label: {
                            LabeledContent("\(PersistenceController.shared.displayName(for: substanceName)) Color") {
                                Image(systemName: "circle.fill").foregroundStyle(selectedColor.wrappedValue.swiftUIColor)
                            }
                        }
                    }
                }
            }
            if !isUnconfirmed, !enabledWebhookPresets.isEmpty {
                Section("Webhooks") {
                    Toggle("Send Webhooks", isOn: sendWebhooks.animation())
                        .tint(.accentColor)

                    if sendWebhooks.wrappedValue {
                        ForEach(enabledWebhookPresets, id: \.objectID) { preset in
                            Toggle(preset.displayName, isOn: $selectedWebhookPresetIDs.contains(preset.idUnwrapped))
                                .tint(.accentColor)
                        }
                    }
                }
            }
            Section {
                if !isUnconfirmed, let routineDraft {
                    Button("Log and Save as Routine…") { save(then: routineDraft) }
                }
                Button("Cancel Logging", role: .cancel, action: dismiss)
            }
        }
        .onChange(of: selectedTime) { _ in
            selectExperienceBasedOnCurrentTime()
        }
        .onAppear {
            generator.prepare()
            initializeWebhooks(with: enabledWebhookPresets.map(\.idUnwrapped))
        }
        .onChange(of: enabledWebhookPresets.map(\.idUnwrapped)) { availableIDs in
            initializeWebhooks(with: availableIDs)
            selectedWebhookPresetIDs.formIntersection(availableIDs)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetToShow, onDismiss: {
            if isSettingUpLoggedRoutine { dismiss() }
        }, content: { sheet in
            switch sheet {
            case .editTitle:
                ExperienceTitleScreen(title: $enteredTitle)
            case .editLocation:
                ChooseLocationScreen(locationManager: locationManager, onDone: { })
            case .editConsumer:
                EditConsumerScreen(consumerName: $consumerName)
            case .setUpRoutine(let draft):
                RoutineScheduleEditor(
                    schedule: draft.schedule, isNew: true, store: .shared, initialProductID: draft.productID)
            }
        })
        .onFirstAppear { // because onAppear is called again when navigating back from color picker screen
            wantsToStartLiveActivity = routineSlot == nil && shouldAutomaticallyStartLiveActivity
            if routineSlot != nil {
                hasSelectedExperience = true
                wantsToForceNewExperience = true
            }
            if let prefillNote, !prefillNote.isEmpty {
                enteredNote = prefillNote
                showsMoreDetails = true
            }
            if let startTime {
                selectedTime = startTime
                if let endTime, endTime > startTime {
                    selectedTimePickerOption = .timeRange
                    selectedEndTime = endTime
                } else {
                    selectedEndTime = startTime.addingTimeInterval(30*60)
                }
            }
            selectExperienceBasedOnCurrentTime()
            locationManager.selectLocation(routineSlot == nil ? locationManager.currentLocation : nil)
            initializeColorCompanionAndNote()
        }
    }

    private func doseDescription(for ingestion: FinishIngestionScreenArguments) -> String {
        guard let dose = ingestion.dose else { return "Unknown amount" }
        return dose.doseDescription(
            units: ingestion.customUnit?.unitUnwrapped ?? ingestion.units ?? "",
            isEstimate: ingestion.isEstimate,
            standardDeviation: ingestion.estimatedDoseStandardDeviation
        )
    }

    private var routineDraft: RoutineDraft? {
        guard routineSlot == nil, let first = ingestions.first else { return nil }
        let product: NSManagedObject
        let name: String
        let kind: RoutineSchedule.ProductKind
        let amount: Double
        if let formulation = first.formulation, let formulationAmount = first.formulationAmount,
           ingestions.allSatisfy({ $0.formulation == formulation && $0.formulationAmount == formulationAmount }) {
            product = formulation
            name = formulation.nameUnwrapped
            kind = .formulation
            amount = formulationAmount
        } else if ingestions.count == 1, let unit = first.customUnit, let dose = first.dose {
            product = unit
            name = unit.nameUnwrapped
            kind = .customUnit
            amount = dose
        } else {
            return nil
        }
        guard !product.isDeleted, !product.objectID.isTemporaryID, amount.isFinite, amount > 0 else { return nil }
        let calendar = RoutineSchedules.calendar
        let time = calendar.dateComponents([.hour, .minute], from: selectedTime)
        let schedule = RoutineSchedule(
            name: name, hour: time.hour ?? 0, minute: time.minute ?? 0,
            productKind: kind, productAmount: amount, anchorDay: .init(.now, calendar: calendar))
        return RoutineDraft(schedule: schedule, productID: product.objectID)
    }

    private func initializeWebhooks(with availableIDs: [UUID]) {
        guard !hasInitializedWebhooks, !availableIDs.isEmpty else { return }
        selectedWebhookPresetIDs = Set(availableIDs)
        hasInitializedWebhooks = true
    }

    private var webhookRecipients: String {
        let names = enabledWebhookPresets
            .filter { selectedWebhookPresetIDs.contains($0.idUnwrapped) }
            .map(\.displayName)
        return names.isEmpty ? "None" : names.formatted(.list(type: .and))
    }

    private var sendWebhooks: Binding<Bool> {
        routineSlot == nil ? $defaultSendWebhooks : $sendRoutineWebhooks
    }

    func selectExperienceBasedOnCurrentTime() {
        experiencesWithinLargerRange = PersistenceController.shared.getExperiences(near: selectedTime)
        if hasSelectedExperience {
            if let selectedExperience, !experiencesWithinLargerRange.contains(selectedExperience) {
                experiencesWithinLargerRange.insert(selectedExperience, at: 0)
            }
        } else {
            selectedExperience = ExperienceLogic.closestExperience(from: experiencesWithinLargerRange, to: selectedTime)
        }
    }

    private var substanceNames: [String] {
        ingestions.map(\.substanceName).uniqued()
    }

    // The administration site is only asked for when every ingestion takes the same route
    private var sharedRoute: AdministrationRoute? {
        let routes = Set(ingestions.map(\.administrationRoute))
        return routes.count == 1 ? routes.first : nil
    }

    private func colorBinding(for substanceName: String) -> Binding<SubstanceColor> {
        Binding {
            selectedColors[substanceName] ?? .fallback
        } set: { color in
            selectedColors[substanceName] = color
        }
    }

    func initializeColorCompanionAndNote() {
        let companions = PersistenceController.shared.getSubstanceCompanions()
        usedColors = companions.map(\.color)
        for substanceName in substanceNames {
            if let companion = companions.first(where: { $0.substanceNameUnwrapped == substanceName }) {
                foundCompanions[substanceName] = companion
                selectedColors[substanceName] = companion.color
            } else {
                // New substances logged together get different colors too
                selectedColors[substanceName] = SubstanceColor.suggested(avoiding: usedColors + selectedColors.values)
            }
        }
    }

    func addIngestionWithExperience() throws {
        let persistence = PersistenceController.shared
        let context = try persistence.journalEditContext()
        let occurrence: RoutineOccurrence?
        if let routineSlot {
            guard let pending = try RoutineSchedules.stageLog(for: routineSlot, in: context) else {
                throw RoutineSchedules.StorageError.alreadyLogged
            }
            occurrence = pending
        } else {
            occurrence = nil
        }
        let selectedLocationValue = locationManager.selectedLocation
        let isNewExperience = selectedExperience == nil
        let experience = try selectedExperience.map { try PersistenceController.journalObject($0, in: context) }
            ?? Experience.create(at: selectedTime, title: enteredTitle, in: context)
        let companions = try Dictionary(uniqueKeysWithValues: substanceNames.map { substanceName in
            (substanceName, try createOrUpdateCompanion(for: substanceName, with: context))
        })
        let newIngestions = try ingestions.map { arguments in
            try createIngestion(
                from: arguments,
                companion: companions[arguments.substanceName],
                with: experience,
                location: selectedLocationValue,
                and: context)
        }
        if isUnconfirmed {
            let confirmationBatchID = newIngestions.count > 1 ? UUID() : nil
            for ingestion in newIngestions {
                ingestion.isUnconfirmed = true
                ingestion.confirmationBatchID = confirmationBatchID
            }
        }
        if let occurrence {
            for ingestion in newIngestions { ingestion.routineOccurrence = occurrence }
        }
        if !isUnconfirmed, let stockContainerID {
            guard let inventoryUse = Inventory.Use(ingestions) else { throw InventoryError.sourceChanged }
            try inventoryUse.stage(using: stockContainerID, for: newIngestions, at: .now, in: context)
        }
        try IngestionSaving.save(newIngestions, sendingWebhooksTo: chosenWebhookPresetObjectIDs)
        let savedExperience = persistence.viewContext.object(with: experience.objectID) as? Experience
        if !isUnconfirmed, let savedExperience {
            startLiveActivityIfWanted(for: savedExperience, isNewExperience: isNewExperience)
        }
    }

    private var chosenWebhookPresetObjectIDs: [NSManagedObjectID] {
        guard !isUnconfirmed, sendWebhooks.wrappedValue else { return [] }
        return enabledWebhookPresets
            .filter { selectedWebhookPresetIDs.contains($0.idUnwrapped) }
            .map(\.objectID)
    }

    // A running activity follows its experience by itself; a new experience starts one, if wanted
    private func startLiveActivityIfWanted(for experience: Experience, isNewExperience: Bool) {
        guard #available(iOS 16.2, *), isNewExperience, wantsToStartLiveActivity, experience.isCurrent else { return }
        Task {
            await ActivityManager.shared.show(experience)
        }
    }

    private func createOrUpdateCompanion(for substanceName: String, with context: NSManagedObjectContext) throws -> SubstanceCompanion {
        let color = colorBinding(for: substanceName).wrappedValue
        if let foundCompanion = foundCompanions[substanceName] {
            let foundCompanion = try PersistenceController.journalObject(foundCompanion, in: context)
            foundCompanion.colorAsText = color.rawValue
            return foundCompanion
        } else {
            let companion = SubstanceCompanion(context: context)
            companion.substanceName = substanceName
            companion.colorAsText = color.rawValue
            return companion
        }
    }

    private func createIngestion(
        from arguments: FinishIngestionScreenArguments,
        companion: SubstanceCompanion?,
        with experience: Experience,
        location: Location?,
        and context: NSManagedObjectContext
    ) throws -> Ingestion {
        let ingestion = Ingestion(context: context)
        ingestion.identifier = UUID()
        ingestion.time = selectedTime
        if selectedTimePickerOption == .timeRange {
            ingestion.endTime = selectedEndTime
        } else {
            ingestion.endTime = nil
        }
        ingestion.creationDate = Date()
        ingestion.customUnit = try arguments.customUnit.map { try PersistenceController.journalObject($0, in: context) }
        ingestion.formulation = try arguments.formulation.map { try PersistenceController.journalObject($0, in: context) }
        ingestion.formulationAmount = arguments.formulationAmount ?? 0
        ingestion.isHiddenInTimeline = arguments.isHiddenInTimeline
        ingestion.dose = arguments.dose ?? 0
        ingestion.units = arguments.units
        ingestion.isEstimate = arguments.isEstimate
        ingestion.estimatedDoseStandardDeviation = arguments.estimatedDoseStandardDeviation ?? 0
        ingestion.note = enteredNote
        ingestion.administrationRoute = arguments.administrationRoute.rawValue
        ingestion.substanceName = arguments.substanceName
        ingestion.color = colorBinding(for: arguments.substanceName).wrappedValue.rawValue
        ingestion.consumerName = Ingestion.storedConsumerName(consumerName)
        let site = siteSelection.siteString(for: arguments.administrationRoute)
        ingestion.administrationSite = site.isEmpty ? nil : site
        ingestion.webhookMessageId = nil
        ingestion.experience = experience
        ingestion.setLocation(location)
        ingestion.substanceCompanion = companion
        return ingestion
    }

    private let generator = UINotificationFeedbackGenerator()

    func generateSuccessHaptic() {
        #if !targetEnvironment(simulator)
        generator.notificationOccurred(.success)
        #endif
    }

    func generateFailedHaptic() {
        #if !targetEnvironment(simulator)
        generator.notificationOccurred(.error)
        #endif
    }}

// swiftlint:enable type_body_length function_body_length file_length


