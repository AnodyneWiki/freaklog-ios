@preconcurrency import CoreData //FIXME
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

struct FinishIngestionScreen: View {
    enum SheetOption: Identifiable {
        case editTitle
        case editLocation
        case editConsumer

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
    @State private var sheetToShow: SheetOption?
    @State private var selectedColors: [String: SubstanceColor] = [:]
    @State private var selectedTime = Date()
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var selectedEndTime = Date().addingTimeInterval(30*60)
    @State private var enteredNote = ""
    @State private var enteredTitle = ""
    @State private var consumerName = ""
    @State private var siteSelection = AdministrationSiteSelection()
    @State private var usedColors = [SubstanceColor]()
    @State private var foundCompanions: [String: SubstanceCompanion] = [:]

    @State private var experiencesWithinLargerRange: [Experience] = []
    @State private var selectedExperience: Experience?
    @State private var wantsToForceNewExperience = false
    @State private var wantsToStartLiveActivity = true
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity: Bool = true

    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest(), animation: .default)
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    @AppStorage(PersistenceController.sendWebhooksEnabledKey) private var isWebhookSectionExpanded: Bool = false
    @State private var selectedWebhookPresetIDs: Set<UUID> = []

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                doneButton
            }
        }
    }

    var doneButton: some View {
        DoneButton {
            do {
                try addIngestionWithExperience()
                toastViewModel.showSuccessToast()
                generateSuccessHaptic()
            } catch {
                toastViewModel.showErrorToast(message: "Failed Ingestion")
                generateFailedHaptic()
            }
            dismiss()
        }
    }

    var screen: some View {
        Form {
            Section("Ingestion") {
                TimePointOrRangePicker(
                    selectedTimePickerOption: $selectedTimePickerOption,
                    selectedTime: $selectedTime,
                    selectedEndTime: $selectedEndTime
                )
                ExperiencePickerRow(
                    selectedExperience: $selectedExperience,
                    wantsToForceNewExperience: $wantsToForceNewExperience,
                    experiences: experiencesWithinLargerRange
                )
                ConsumerRow(consumerName: consumerName) { sheetToShow = .editConsumer }
                if let sharedRoute {
                    AdministrationSitePicker(route: sharedRoute, selection: $siteSelection)
                }
                LocationButton(locationName: locationManager.selectedLocation?.name) { sheetToShow = .editLocation }
            }
            .listRowSeparator(.hidden)
            .onChange(of: selectedTime) { _ in
                selectExperienceBasedOnCurrentTime()
            }
            Section("Notes") {
                TextField("Enter Note", text: $enteredNote, axis: .vertical)
                    .autocapitalization(.sentences)
            }
            if selectedExperience == nil {
                Section("New Experience") {
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
                        if LiveActivities.areAvailable, !ActivityManager.shared.isActivityActive, isTimeRecentOrFuture {
                            Toggle("Start Live Activity", isOn: $wantsToStartLiveActivity).tint(.accentColor)
                        }
                    }
                }
            }
            Section {
                ForEach(substanceNames, id: \.self) { substanceName in
                    let selectedColor = colorBinding(for: substanceName)
                    NavigationLink {
                        ColorPickerScreen(
                            selectedColor: selectedColor,
                            usedColors: usedColors)
                    } label: {
                        HStack {
                            Text("\(PersistenceController.shared.displayName(for: substanceName)) Color")
                            Spacer()
                            Image(systemName: "circle.fill").foregroundColor(selectedColor.wrappedValue.swiftUIColor)
                        }
                    }
                }
            }
            if !enabledWebhookPresets.isEmpty {
                Section("Webhooks") {
                    Toggle("Send Webhooks", isOn: $isWebhookSectionExpanded.animation())
                        .tint(.accentColor)

                    if isWebhookSectionExpanded {
                        ForEach(enabledWebhookPresets, id: \.objectID) { preset in
                            HStack {
                                Text(preset.displayName)
                                Spacer()
                                if selectedWebhookPresetIDs.contains(preset.idUnwrapped) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let presetId = preset.idUnwrapped
                                if selectedWebhookPresetIDs.contains(presetId) {
                                    selectedWebhookPresetIDs.remove(presetId)
                                } else {
                                    selectedWebhookPresetIDs.insert(presetId)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            wantsToStartLiveActivity = shouldAutomaticallyStartLiveActivity
            generator.prepare()
            // Preserve previously selected presets; if none stored, default to all enabled
            if selectedWebhookPresetIDs.isEmpty {
                selectedWebhookPresetIDs = Set(enabledWebhookPresets.map { $0.idUnwrapped })
            }
        }
        .onChange(of: enabledWebhookPresets.count) { _ in
            let availableIDs = Set(enabledWebhookPresets.map { $0.idUnwrapped })
            // Drop selections that no longer exist and default to all when empty
            selectedWebhookPresetIDs = selectedWebhookPresetIDs.intersection(availableIDs)
            if selectedWebhookPresetIDs.isEmpty {
                selectedWebhookPresetIDs = availableIDs
            }
        }
        .navigationBarTitle("Finish Ingestion")
        .sheet(item: $sheetToShow, content: { sheet in
            switch sheet {
            case .editTitle:
                ExperienceTitleScreen(title: $enteredTitle)
            case .editLocation:
                ChooseLocationScreen(locationManager: locationManager, onDone: { })
            case .editConsumer:
                EditConsumerScreen(consumerName: $consumerName)
            }
        })
        .onFirstAppear { // because onAppear is called again when navigating back from color picker screen
            if let startTime {
                selectedTime = startTime
                selectedEndTime = startTime.addingTimeInterval(30*60)
            }
            selectExperienceBasedOnCurrentTime()
            locationManager.selectLocation(locationManager.currentLocation)
            initializeColorCompanionAndNote()
        }
    }

    func selectExperienceBasedOnCurrentTime() {
        experiencesWithinLargerRange = PersistenceController.shared.getExperiences(near: selectedTime)
        if wantsToForceNewExperience {
            selectedExperience = nil
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
        let context = PersistenceController.shared.viewContext
        let selectedLocationValue = locationManager.selectedLocation
        let isNewExperience = selectedExperience == nil
        let experience = selectedExperience ?? Experience.create(at: selectedTime, title: enteredTitle, in: context)
        let companions = Dictionary(uniqueKeysWithValues: substanceNames.map { substanceName in
            (substanceName, createOrUpdateCompanion(for: substanceName, with: context))
        })
        let newIngestions = ingestions.map { arguments in
            createIngestion(
                from: arguments,
                companion: companions[arguments.substanceName],
                with: experience,
                location: selectedLocationValue,
                and: context)
        }
        try IngestionSaving.save(newIngestions, sendingWebhooksTo: chosenWebhookPresetObjectIDs)
        startLiveActivityIfWanted(for: experience, isNewExperience: isNewExperience)
    }

    private var chosenWebhookPresetObjectIDs: [NSManagedObjectID] {
        guard isWebhookSectionExpanded else { return [] }
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

    private func createOrUpdateCompanion(for substanceName: String, with context: NSManagedObjectContext) -> SubstanceCompanion {
        let color = colorBinding(for: substanceName).wrappedValue
        if let foundCompanion = foundCompanions[substanceName] {
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
        and context: NSManagedObjectContext) -> Ingestion
    {
        let ingestion = Ingestion(context: context)
        ingestion.identifier = UUID()
        ingestion.time = selectedTime
        if selectedTimePickerOption == .timeRange {
            ingestion.endTime = selectedEndTime
        } else {
            ingestion.endTime = nil
        }
        ingestion.creationDate = Date()
        ingestion.customUnit = arguments.customUnit
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


