@preconcurrency import CoreData //FIXME
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

struct FinishIngestionScreen: View {
    struct RoutineDraft: Hashable {
        let schedule: RoutineSchedule
        let productID: NSManagedObjectID
    }

    enum SheetOption: Identifiable, Hashable {
        case editLocation
        case editConsumer
        case editMeasurement
        case setUpRoutine(RoutineDraft)

        var id: Self {
            self
        }
    }

    // Logged together with the same time, experience, consumer, location and note,
    // like the substances of a formulation
    @State private var ingestions: [FinishIngestionScreenArguments]
    let dismiss: () -> Void

    init(arguments: FinishIngestionScreenArguments, dismiss: @escaping () -> Void) {
        self.init(ingestions: [arguments], dismiss: dismiss)
    }

    init(ingestions: [FinishIngestionScreenArguments], dismiss: @escaping () -> Void) {
        _ingestions = State(initialValue: ingestions)
        self.dismiss = dismiss
    }

    @EnvironmentObject private var toastViewModel: ToastViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.addIngestionStartTime) private var startTime
    @Environment(\.addIngestionEndTime) private var endTime
    @Environment(\.ingestionPrefillNote) private var prefillNote
    @Environment(\.routineOccurrenceSlot) private var routineSlot
    @Environment(\.requiresIngestionAmount) private var requiresAmount
    @State private var sheetToShow: SheetOption?
    @State private var selectedColors: [String: SubstanceColor] = [:]
    @State private var selectedTime = Date()
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var selectedEndTime = Date().addingTimeInterval(30*60)
    @State private var enteredNote = ""
    @State private var showsDisplayOptions = false
    @State private var showsWebhooks = false
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
            ToolbarItem(placement: .confirmationAction) {
                doneButton
            }
        }
    }

    var doneButton: some View {
        Button(isUnconfirmed ? "Save" : "Log", action: save)
            .font(.headline)
            .disabled(isSettingUpLoggedRoutine || needsAmount)
    }

    private func save() {
        guard !needsAmount else { return }
        save(then: nil)
    }

    private func save(then routine: RoutineDraft?) {
        guard !isSettingUpLoggedRoutine, !needsAmount else { return }
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
            ingestionSummary
            Section("When") {
                TimePointOrRangePicker(
                    selectedTimePickerOption: $selectedTimePickerOption,
                    selectedTime: $selectedTime,
                    selectedEndTime: $selectedEndTime,
                    showsPresets: true
                )
                if let routineSlot {
                    LabeledContent("Scheduled") {
                        Text(routineSlot.scheduledAt, format: .dateTime.month().day().hour().minute())
                    }
                }
            }
            experienceSection
            Section {
                Toggle("Unconfirmed", isOn: $isUnconfirmed)
            } footer: {
                if isUnconfirmed {
                    Text("Confirm this entry in Journal to count it in totals, use stock, or send webhooks.")
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
            Section("Details") {
                TextField("Note", text: $enteredNote, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                ConsumerRow(consumerName: consumerName) { sheetToShow = .editConsumer }
                if let sharedRoute {
                    AdministrationSitePicker(route: sharedRoute, selection: $siteSelection)
                }
                LocationButton(locationName: locationManager.selectedLocation?.name) { sheetToShow = .editLocation }
                if #available(iOS 16.2, *), selectedExperience == nil, !isUnconfirmed,
                   LiveActivities.areAvailable, !ActivityManager.shared.isActivityActive,
                   selectedTime > Date.now.addingTimeInterval(-12 * 60 * 60) {
                    Toggle("Start Live Activity", isOn: $wantsToStartLiveActivity)
                }
                displayOptions
            }
            if !isUnconfirmed, !enabledWebhookPresets.isEmpty {
                sharingSection
            }
            if !isUnconfirmed, let routineDraft {
                Section {
                    Button("Log and Save as Routine…") { save(then: routineDraft) }
                }
            }
        }
        .onChange(of: selectedTimeRange) { _ in
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
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetToShow, onDismiss: {
            if isSettingUpLoggedRoutine { dismiss() }
        }, content: { sheet in
            switch sheet {
            case .editLocation:
                ChooseLocationScreen(locationManager: locationManager, onDone: { })
            case .editConsumer:
                EditConsumerScreen(consumerName: $consumerName)
            case .editMeasurement:
                if let ingestion = ingestions.first {
                    IngestionMeasurementEditor(ingestion: ingestion, onDone: updateMeasurement)
                }
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

    private var ingestionSummary: some View {
        Section {
            ForEach(ingestions.indices, id: \.self) { index in
                let ingestion = ingestions[index]
                if ingestions.count == 1, ingestion.formulation == nil, routineSlot == nil {
                    Button {
                        sheetToShow = .editMeasurement
                    } label: {
                        summary(for: ingestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the ingestion details editor")
                } else {
                    summary(for: ingestion)
                }
            }
            if needsAmount {
                Button("Enter Amount") { sheetToShow = .editMeasurement }
            }
        }
    }

    private var needsAmount: Bool {
        requiresAmount && ingestions.first?.dose.map { $0.isFinite && $0 > 0 } != true
    }

    private func summary(for ingestion: FinishIngestionScreenArguments) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PersistenceController.shared.displayName(for: ingestion.substanceName))
                .font(.headline)
            if requiresAmount, let unitName = ingestion.customUnit?.nameUnwrapped, !unitName.isEmpty {
                Text(unitName).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(doseDescription(for: ingestion))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(ingestion.administrationRoute.rawValue.localizedCapitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func updateMeasurement(_ updated: FinishIngestionScreenArguments) {
        let previous = ingestions[0]
        if updated.administrationRoute != previous.administrationRoute {
            siteSelection = AdministrationSiteSelection()
            stockContainerID = nil
        } else if updated.customUnit != previous.customUnit || updated.units != previous.units || updated.dose == nil {
            stockContainerID = nil
        }
        ingestions[0] = updated
    }

    private var experienceSection: some View {
        Section("Experience") {
            if experiencesWithinLargerRange.isEmpty {
                LabeledContent("Add To", value: "New Experience")
            } else {
                ExperiencePickerRow(
                    selectedExperience: $selectedExperience,
                    wantsToForceNewExperience: $wantsToForceNewExperience,
                    experiences: experiencesWithinLargerRange,
                    onSelection: { hasSelectedExperience = true }
                )
            }
            if selectedExperience == nil {
                TextField("Title (Optional)", text: $enteredTitle)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    private var displayOptions: some View {
        DisclosureGroup("Journal Colors", isExpanded: $showsDisplayOptions) {
            ForEach(substanceNames, id: \.self) { substanceName in
                let color = colorBinding(for: substanceName)
                NavigationLink {
                    ColorPickerScreen(selectedColor: color, usedColors: usedColors)
                } label: {
                    LabeledContent {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(color.wrappedValue.swiftUIColor)
                            .accessibilityLabel(Text(color.wrappedValue.name))
                    } label: {
                        if substanceNames.count == 1 {
                            Text("Journal Color")
                        } else {
                            Text(PersistenceController.shared.displayName(for: substanceName))
                        }
                    }
                }
            }
        }
    }

    private var sharingSection: some View {
        Section("Sharing") {
            DisclosureGroup(isExpanded: $showsWebhooks) {
                Toggle("Send Webhooks", isOn: sendWebhooks)
                if sendWebhooks.wrappedValue {
                    ForEach(enabledWebhookPresets, id: \.objectID) { preset in
                        Toggle(preset.displayName, isOn: $selectedWebhookPresetIDs.contains(preset.idUnwrapped))
                    }
                }
            } label: {
                LabeledContent("Webhooks", value: sendWebhooks.wrappedValue ? webhookRecipients : String(localized: "Off"))
            }
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
        let dates = selectedTimeRange
        experiencesWithinLargerRange = PersistenceController.shared.getExperiences(near: dates)
        if hasSelectedExperience {
            if let selectedExperience, !experiencesWithinLargerRange.contains(selectedExperience) {
                experiencesWithinLargerRange.insert(selectedExperience, at: 0)
            }
        } else {
            selectedExperience = ExperienceLogic.closestExperience(from: experiencesWithinLargerRange, to: dates)
        }
    }

    private var selectedTimeRange: ClosedRange<Date> {
        selectedTime...((selectedTimePickerOption == .timeRange) ? max(selectedTime, selectedEndTime) : selectedTime)
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

private struct RequiresIngestionAmountKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var requiresIngestionAmount: Bool {
        get { self[RequiresIngestionAmountKey.self] }
        set { self[RequiresIngestionAmountKey.self] = newValue }
    }
}

private struct IngestionMeasurementEditor: View {
    let ingestion: FinishIngestionScreenArguments
    let onDone: (FinishIngestionScreenArguments) -> Void
    private let initialAmountText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requiresIngestionAmount) private var requiresAmount
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @FocusState private var isAmountFocused: Bool
    @State private var route: AdministrationRoute
    @State private var amountText: String
    @State private var didChangeRoute = false
    @State private var units: String
    @State private var isEstimate: Bool
    @State private var deviation: Double?

    init(ingestion: FinishIngestionScreenArguments, onDone: @escaping (FinishIngestionScreenArguments) -> Void) {
        self.ingestion = ingestion
        self.onDone = onDone
        _route = State(initialValue: ingestion.administrationRoute)
        let formattedAmount = ingestion.dose?.formatted() ?? ""
        _amountText = State(initialValue: formattedAmount)
        initialAmountText = formattedAmount
        _units = State(initialValue: ingestion.units ?? "")
        _isEstimate = State(initialValue: ingestion.isEstimate)
        _deviation = State(initialValue: ingestion.estimatedDoseStandardDeviation)
    }

    private var customUnit: CustomUnit? {
        route == ingestion.administrationRoute ? ingestion.customUnit : nil
    }

    private var amount: Double? {
        if !didChangeRoute, amountText == initialAmountText { return ingestion.dose }
        return getDouble(from: amountText)
    }
    private var amountIsValid: Bool {
        guard let amount else { return amountText.isEmpty && !requiresAmount }
        return amount.isFinite && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEyeOpen && !requiresAmount {
                    Section {
                        Picker("Route", selection: $route) {
                            ForEach(AdministrationRoute.allCases) { route in
                                Text(route.rawValue.localizedCapitalized).tag(route)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .onChange(of: route, perform: resetAmount)
                    } footer: {
                        Text("Changing the route clears the amount.")
                    }
                }
                Section {
                    if let customUnit {
                        LabeledContent("Unit", value: customUnit.unitUnwrapped)
                    } else {
                        UnitsPicker(units: $units).id(route)
                    }
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                    if amount != nil {
                        EstimateFields(
                            isEstimate: $isEstimate,
                            standardDeviation: $deviation,
                            units: customUnit?.unitUnwrapped ?? units,
                            mean: amount
                        )
                    }
                } footer: {
                    if !requiresAmount {
                        Text("Leave the amount blank to log it as unknown.")
                    }
                }
            }
            .onAppear { isAmountFocused = requiresAmount }
            .navigationTitle("Edit Ingestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: apply)
                        .disabled(!amountIsValid || (amount != nil && customUnit == nil && units.isEmpty))
                }
            }
        }
    }

    private func resetAmount(for route: AdministrationRoute) {
        didChangeRoute = true
        amountText = ""
        isEstimate = false
        deviation = nil
        units = route == ingestion.administrationRoute
            ? ingestion.units ?? ""
            : PersistenceController.shared.getCustomSubstance(name: ingestion.substanceName)?.unitsUnwrapped
                ?? PersistenceController.shared.resolvedDose(for: ingestion.substanceName, route: route)?.units
                ?? UnitPickerOptions.mg.rawValue
    }

    private func apply() {
        var updated = FinishIngestionScreenArguments(
            substanceName: ingestion.substanceName,
            administrationRoute: route,
            dose: amount,
            units: units.isEmpty ? nil : units,
            isEstimate: amount != nil && isEstimate,
            estimatedDoseStandardDeviation: amount != nil && isEstimate ? deviation : nil,
            customUnit: customUnit
        )
        updated.isHiddenInTimeline = ingestion.isHiddenInTimeline
        onDone(updated)
        dismiss()
    }
}
