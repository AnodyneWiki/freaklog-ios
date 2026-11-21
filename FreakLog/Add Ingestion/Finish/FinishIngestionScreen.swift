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

    let arguments: FinishIngestionScreenArguments
    let dismiss: () -> Void

    @EnvironmentObject private var toastViewModel: ToastViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @State private var sheetToShow: SheetOption?
    @State private var selectedColor = SubstanceColor.allCases.randomElement() ?? SubstanceColor.blue
    @State private var selectedTime = Date()
    @State private var selectedTimePickerOption = TimePickerOption.pointInTime
    @State private var selectedEndTime = Date().addingTimeInterval(30*60)
    @State private var enteredNote = ""
    @State private var enteredTitle = ""
    @State private var consumerName = ""
    @State private var siteSelection = AdministrationSiteSelection()
    @State private var usedColors = [SubstanceColor]()
    @State private var foundCompanion: SubstanceCompanion?

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
                Task { await LeaderboardSyncManager.shared.syncAll() }
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
                AdministrationSitePicker(route: arguments.administrationRoute, selection: $siteSelection)
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
                NavigationLink {
                    ColorPickerScreen(
                        selectedColor: $selectedColor,
                        usedColors: usedColors)
                } label: {
                    HStack {
                        Text("\(arguments.substanceName) Color")
                        Spacer()
                        Image(systemName: "circle.fill").foregroundColor(selectedColor.swiftUIColor)
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
            let lastIngestionTimeIntervalSince1970 = UserDefaults.standard.double(forKey: PersistenceController.lastIngestionTimeOfExperienceWhereAddIngestionTappedKey)
            let clonedIngestionTimeIntervalSince1970 = UserDefaults.standard.double(forKey: PersistenceController.clonedIngestionTimeKey)
            if clonedIngestionTimeIntervalSince1970 != 0 {
                let clonedTime = Date(timeIntervalSince1970: clonedIngestionTimeIntervalSince1970)
                selectedTime = clonedTime
                selectedEndTime = clonedTime.addingTimeInterval(30*60)
            } else if lastIngestionTimeIntervalSince1970 != 0 {
                let lastIngestionTimeOfExperienceWhereAddIngestionTapped = Date(timeIntervalSince1970: lastIngestionTimeIntervalSince1970)
                let hoursSince = lastIngestionTimeOfExperienceWhereAddIngestionTapped.distance(to: .now)/(60*60)
                if hoursSince > 20 {
                    selectedTime = lastIngestionTimeOfExperienceWhereAddIngestionTapped
                    selectedEndTime = lastIngestionTimeOfExperienceWhereAddIngestionTapped.addingTimeInterval(30*60)
                }
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
            selectedExperience = FinishIngestionScreen.getClosestExperience(
                from: experiencesWithinLargerRange,
                date: selectedTime)
        }
    }

    func initializeColorCompanionAndNote() {
        let companions = PersistenceController.shared.getSubstanceCompanions()
        usedColors = companions.map(\.color)
        let companionMatch = companions.first { comp in
            comp.substanceNameUnwrapped == arguments.substanceName
        }
        if let companionMatchUnwrap = companionMatch {
            foundCompanion = companionMatchUnwrap
            selectedColor = companionMatchUnwrap.color
        } else {
            selectedColor = SubstanceColor.suggested(avoiding: usedColors)
        }
    }

    private func siteString() -> String {
        siteSelection.siteString(for: arguments.administrationRoute)
    }

    func addIngestionWithExperience() throws {
        let context = PersistenceController.shared.viewContext
        let selectedLocationValue = locationManager.selectedLocation
        let isNewExperience = selectedExperience == nil

        try context.performAndWait {
            let experience = selectedExperience ?? Experience.create(at: selectedTime, title: enteredTitle, in: context)
            let ingestion = createIngestionWithCompanion(with: experience, location: selectedLocationValue, and: context)
            try context.save()
            startLiveActivityIfWanted(for: experience, isNewExperience: isNewExperience)

            if isWebhookSectionExpanded, !selectedWebhookPresetIDs.isEmpty {
                let presetObjectIDs = enabledWebhookPresets
                    .filter { selectedWebhookPresetIDs.contains($0.idUnwrapped) }
                    .map { $0.objectID }
                WebhookManager.shared.sendWebhooks(for: ingestion, presetObjectIDs: presetObjectIDs)
            }
        }
    }

    // A running activity follows its experience by itself; a new experience starts one, if wanted
    private func startLiveActivityIfWanted(for experience: Experience, isNewExperience: Bool) {
        guard #available(iOS 16.2, *), isNewExperience, wantsToStartLiveActivity, experience.isCurrent else { return }
        Task {
            await ActivityManager.shared.show(experience)
        }
    }

    private func createOrUpdateCompanion(with context: NSManagedObjectContext) -> SubstanceCompanion {
        if let foundCompanion {
            foundCompanion.colorAsText = selectedColor.rawValue
            return foundCompanion
        } else {
            let companion = SubstanceCompanion(context: context)
            companion.substanceName = arguments.substanceName
            companion.colorAsText = selectedColor.rawValue
            return companion
        }
    }

    @discardableResult
    private func createIngestionWithCompanion(
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
        ingestion.color = selectedColor.rawValue
        ingestion.consumerName = Ingestion.storedConsumerName(consumerName)
        let site = siteString()
        ingestion.administrationSite = site.isEmpty ? nil : site
        ingestion.webhookMessageId = nil
        ingestion.experience = experience
        ingestion.setLocation(location)
        let companion = createOrUpdateCompanion(with: context)
        ingestion.substanceCompanion = companion
        return ingestion
    }

    private static func getClosestExperience(from experiences: [Experience], date: Date) -> Experience? {
        let fifteenHours: TimeInterval = 15 * 60 * 60
        let threeHours: TimeInterval = 3 * 60 * 60
        return experiences.first { exp in
            let experienceStart = exp.ingestionsSorted.first?.time ?? exp.sortDateUnwrapped
            let lastIngestionTime = exp.ingestionsSorted.last?.time ?? exp.sortDateUnwrapped
            let experienceRange = experienceStart.addingTimeInterval(-threeHours) ... max(experienceStart.addingTimeInterval(fifteenHours), lastIngestionTime.addingTimeInterval(threeHours))
            return experienceRange.contains(date)
        }
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


