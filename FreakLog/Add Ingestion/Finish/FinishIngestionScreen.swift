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
    @State private var selectedNostril: Nostril?
    @State private var selectedVein: Vein?
    @State private var selectedMuscle: Muscle?
    @State private var selectedSubQSite: SubcutaneousSite?
    @State private var alreadyUsedColors = [SubstanceColor]()
    @State private var otherColors = [SubstanceColor]()
    @State private var foundCompanion: SubstanceCompanion?

    @State private var experiencesWithinLargerRange: [Experience] = []
    @State private var selectedExperience: Experience?
    @State private var wantsToForceNewExperience = false
    @State private var wantsToStartLiveActivity = true
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent = true
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity: Bool = true

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WebhookPreset.name, ascending: true)],
        predicate: NSPredicate(format: "isEnabled == YES"),
        animation: .default
    )
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    @AppStorage(PersistenceController.sendWebhooksEnabledKey) private var isWebhookSectionExpanded: Bool = false
    @State private var selectedWebhookPresetIDs: Set<UUID> = []

    var areYouConsumer: Bool {
        consumerName.isEmpty || consumerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
            Task { @MainActor in
                do {
                    try addIngestionWithExperience()
                    Task { @MainActor in
                        toastViewModel.showSuccessToast()
                        generateSuccessHaptic()
                        dismiss()
                    }
                } catch {
                    Task { @MainActor in
                        toastViewModel.showErrorToast(message: "Failed Ingestion")
                        generateFailedHaptic()
                        dismiss()
                    }
                }
            }
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
                routeSpecificPickers
                Button {
                    sheetToShow = .editLocation
                } label: {
                    if let locationName = locationManager.selectedLocation?.name {
                        Label(locationName, systemImage: "mappin")
                    } else {
                        Label("Add Location", systemImage: "plus")
                    }
                }
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
                        let isTimeRecentOrFuture = Date().timeIntervalSinceReferenceDate - selectedTime
                            .timeIntervalSinceReferenceDate < 12 * 60 * 60
                        if
                            !ProcessInfo.processInfo.isiOSAppOnMac,
                            ActivityManager.shared.authorizationInfo.areActivitiesEnabled,
                            !ActivityManager.shared.isActivityActive,
                            isTimeRecentOrFuture
                        {
                            Toggle("Start Live Activity", isOn: $wantsToStartLiveActivity).tint(.accentColor)
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    ColorPickerScreen(
                        selectedColor: $selectedColor,
                        alreadyUsedColors: alreadyUsedColors,
                        otherColors: otherColors)
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
                                Text(preset.nameUnwrapped.isEmpty ? "Unnamed" : preset.nameUnwrapped)
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
            locationManager.selectedLocation = locationManager.currentLocation
            locationManager.selectedLocationName = locationManager.currentLocation?.name ?? ""
            initializeColorCompanionAndNote()
        }
    }

    func selectExperienceBasedOnCurrentTime() {
        let fetchRequest = Experience.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        fetchRequest.predicate = FinishIngestionScreen.getPredicate(from: selectedTime)
        experiencesWithinLargerRange = (try? PersistenceController.shared.viewContext.fetch(fetchRequest)) ?? []
        if wantsToForceNewExperience {
            selectedExperience = nil
        } else {
            selectedExperience = FinishIngestionScreen.getClosestExperience(
                from: experiencesWithinLargerRange,
                date: selectedTime)
        }
    }

    func initializeColorCompanionAndNote() {
        let fetchRequest = SubstanceCompanion.fetchRequest()
        let companions = (try? PersistenceController.shared.viewContext.fetch(fetchRequest)) ?? []
        alreadyUsedColors = Array(Set(companions.map { $0.color })).sorted()
        otherColors = Array(Set(SubstanceColor.allCases).subtracting(alreadyUsedColors)).sorted()
        let companionMatch = companions.first { comp in
            comp.substanceNameUnwrapped == arguments.substanceName
        }
        if let companionMatchUnwrap = companionMatch {
            foundCompanion = companionMatchUnwrap
            selectedColor = companionMatchUnwrap.color
        } else {
            selectedColor = otherColors.filter { $0.isPreferred }.first ?? otherColors.first ?? SubstanceColor.allCases
                .randomElement() ?? SubstanceColor.blue
        }
    }

    @ViewBuilder
    var routeSpecificPickers: some View {
        switch arguments.administrationRoute {
        case .oral:
            EmptyView()
        case .insufflated:
            NostrilPicker(selection: $selectedNostril)
                .pickerStyle(.menu)
        case .intravenous:
            VeinPicker(selection: $selectedVein)
                .pickerStyle(.menu)
        case .intramuscular:
            MusclePicker(selection: $selectedMuscle)
                .pickerStyle(.menu)
        case .subcutaneous:
            SubQSitePicker(selection: $selectedSubQSite)
                .pickerStyle(.menu)
        default:
            EmptyView()
        }
    }

    func getSiteString() -> String {
        if arguments.administrationRoute == .insufflated, let val = selectedNostril {
            return val.rawValue
        } else if arguments.administrationRoute == .intravenous, let val = selectedVein {
            return val.rawValue
        } else if arguments.administrationRoute == .intramuscular, let val = selectedMuscle {
            return val.rawValue
        } else if arguments.administrationRoute == .subcutaneous, let val = selectedSubQSite {
            return val.rawValue
        }
        return ""
    }

    func addIngestionWithExperience() throws {
        let context = PersistenceController.shared.viewContext
        var createdIngestion: Ingestion?
        var isActivityActive = false
        if #available(iOS 16.2, *) {
            isActivityActive = ActivityManager.shared.isActivityActive
        }
        let selectedLocationValue = locationManager.selectedLocation

        try context.performAndWait {
            if let existingExperience = selectedExperience {
                createdIngestion = createIngestionWithCompanion(
                    with: existingExperience,
                    location: selectedLocationValue,
                    and: context)
                if #available(iOS 16.2, *) {
                    if existingExperience.isCurrent, isActivityActive {
                        Task {
                            await ActivityManager.shared.startOrUpdateActivity(
                                substanceGroups: getSubstanceIngestionGroups(ingestions: existingExperience.myIngestionsSorted),
                                everythingForEachRating: existingExperience.ratingsWithTimeSorted.map { shulgin in
                                    EverythingForOneRating(
                                        time: shulgin.timeUnwrapped,
                                        option: shulgin.optionUnwrapped)
                                },
                                everythingForEachTimedNote: existingExperience.timedNotesSorted.filter { $0.isPartOfTimeline }
                                    .map { timedNote in
                                        EverythingForOneTimedNote(
                                            time: timedNote.timeUnwrapped,
                                            color: timedNote.color)
                                    },
                                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                            )
                        }
                    }
                }
            } else {
                let newExperience = Experience(context: context)
                newExperience.creationDate = Date()
                newExperience.sortDate = selectedTime
                var title = selectedTime.asDateString
                if !enteredTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = enteredTitle
                }
                newExperience.title = title
                newExperience.text = ""
                createdIngestion = createIngestionWithCompanion(
                    with: newExperience,
                    location: selectedLocationValue,
                    and: context)
                if #available(iOS 16.2, *) {
                    if newExperience.isCurrent, self.wantsToStartLiveActivity {
                        Task {
                            await ActivityManager.shared.startOrUpdateActivity(
                                substanceGroups: getSubstanceIngestionGroups(ingestions: newExperience.myIngestionsSorted),
                                everythingForEachRating: [],
                                everythingForEachTimedNote: [],
                                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                            )
                        }
                    }
                }
            }
            try context.save()

            if isWebhookSectionExpanded,
               !selectedWebhookPresetIDs.isEmpty,
               let ingestion = createdIngestion {

                let dose = arguments.dose ?? 0
                let units: String
                if let customUnit = arguments.customUnit {
                    units = dose.justUnit(pluralizableUnit: customUnit.pluralizableUnit)
                } else {
                    units = arguments.units ?? ""
                }

                let snapshot = WebhookManager.WebhookDataSnapshot(
                    user: areYouConsumer ? "" : consumerName,
                    substance: arguments.substanceName,
                    dose: dose,
                    units: units,
                    isEstimate: arguments.isEstimate,
                    route: arguments.administrationRoute.rawValue,
                    site: getSiteString().lowercased(),
                    note: enteredNote
                )

                let presetObjectIDs = enabledWebhookPresets
                    .filter { selectedWebhookPresetIDs.contains($0.idUnwrapped) }
                    .map { $0.objectID }
                let ingestionObjectID = ingestion.objectID
                
                WebhookManager.shared.sendWebhooks(
                    ingestionObjectID: ingestionObjectID,
                    presetObjectIDs: presetObjectIDs,
                    dataSnapshot: snapshot
                )
            }
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
        if !areYouConsumer {
            ingestion.consumerName = consumerName
        }
        let siteString = getSiteString()
        if !siteString.isEmpty {
            ingestion.administrationSite = siteString
        } else {
            ingestion.administrationSite = nil
        }
        ingestion.webhookMessageId = nil
        ingestion.experience = experience
        if let location {
            let newLocation = ExperienceLocation(context: context)
            newLocation.name = location.name
            newLocation.latitude = location.latitude ?? 0
            newLocation.longitude = location.longitude ?? 0
            ingestion.location = newLocation
        }
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

    static func getPredicate(from date: Date) -> NSCompoundPredicate {
        let longInterval: TimeInterval = 60 * 60 * 60
        let startDate = date.addingTimeInterval(-longInterval)
        let endDate = date.addingTimeInterval(longInterval)
        let laterThanStart = NSPredicate(format: "sortDate > %@", startDate as NSDate)
        let earlierThanEnd = NSPredicate(format: "sortDate < %@", endDate as NSDate)
        return NSCompoundPredicate(
            andPredicateWithSubpredicates: [laterThanStart, earlierThanEnd])
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
    }

    static func updateIngestionWithWebhookMessageId(ingestion: Ingestion, messageId: String) async throws {
        let ingestionObjectID = ingestion.objectID
        let context = PersistenceController.shared.viewContext
        try await context.perform {
            if let ingestionInContext = context.object(with: ingestionObjectID) as? Ingestion {
                ingestionInContext.webhookMessageId = messageId
                try context.save()
            }
        }
    }

    static func deleteWebhookMessages(for ingestions: [Ingestion]) async {
        await WebhookManager.shared.deleteWebhookMessages(for: ingestions)
    }

    static func deleteWebhookMessageIfNeeded(for ingestion: Ingestion) async {
        await WebhookManager.shared.deleteWebhookMessages(for: [ingestion])
    }

    static func deleteWebhookMessageIfNeeded(forID ingestionID: NSManagedObjectID) async {
        await WebhookManager.shared.deleteWebhookMessages(forIngestionObjectIDs: [ingestionID])
    }
}

// swiftlint:enable type_body_length function_body_length file_length


