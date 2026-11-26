import SwiftUI
import CoreData
import AppIntents

extension View {
    // Visibility is stored on entries and their companions, so a change may
    // leave the experience's own fields and relationships untouched.
    func observeExperienceTimeline(_ experience: Experience) -> some View {
        onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: experience.managedObjectContext
        )) { change in
            let keys = [NSUpdatedObjectsKey, NSRefreshedObjectsKey]
            if keys.contains(where: { key in
                let objects = change.userInfo?[key] as? Set<NSManagedObject> ?? []
                return objects.contains {
                    if let entry = $0 as? Ingestion { return entry.experience == experience }
                    if let rating = $0 as? ShulginRating { return rating.experience == experience }
                    if let companion = $0 as? SubstanceCompanion {
                        return companion.ingestionsUnwrapped.contains { $0.experience == experience }
                    }
                    return false
                }
            }) {
                experience.objectWillChange.send()
            }
        }
    }
}

private struct HiddenTimelineItemsScreen: View {
    @ObservedObject var experience: Experience
    let includesRatings: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showsSaveError = false

    var body: some View {
        let ingestions = experience.ingestionsSorted.filter(\.isHiddenFromTimeline)
        let ratings = includesRatings ? experience.ratingsWithTimeSorted.filter(\.isHiddenInTimeline) : []
        let companions = ingestions.compactMap(\.substanceCompanion)
            .filter(\.isHiddenInTimeline).uniqued()
        List {
            if ingestions.isEmpty, ratings.isEmpty, companions.isEmpty {
                Text("Nothing is hidden from this timeline.")
                    .foregroundStyle(.secondary)
            }
            if !ingestions.isEmpty {
                Section("Ingestions") {
                    ForEach(ingestions) { ingestion in
                        item(ingestion.substanceDisplayName, date: ingestion.time) {
                            update(ingestion) { $0.timelineVisibility = .show }
                        }
                    }
                }
            }
            if !ratings.isEmpty {
                Section("Ratings") {
                    ForEach(ratings) { rating in
                        item(rating.optionUnwrapped.stringRepresentation, date: rating.time) {
                            update(rating) { $0.isHiddenInTimeline = false }
                        }
                    }
                }
            }
            if !companions.isEmpty {
                Section {
                    ForEach(companions) { companion in
                        item(PersistenceController.shared.displayName(for: companion.substanceNameUnwrapped)) {
                            update(companion) { $0.isHiddenInTimeline = false }
                        }
                    }
                } header: {
                    Text("Hidden by Default")
                } footer: {
                    Text("Showing one of these substances changes its default for all timelines.")
                }
            }
        }
        .navigationTitle("Hidden Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Couldn’t Update the Timeline", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        }
        .observeExperienceTimeline(experience)
    }

    private func item(_ name: String, date: Date? = nil, show: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                if let date {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Show", action: show)
                .buttonStyle(.borderless)
                .accessibilityLabel("Show \(name) in Timeline")
        }
    }

    private func update<T: NSManagedObject>(_ record: T, change: (T) -> Void) {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let editable = try PersistenceController.journalObject(record, in: context)
            change(editable)
            try context.save()
        } catch {
            showsSaveError = true
        }
    }
}

// swiftlint:disable type_body_length
struct ExperienceScreen: View {
    @ObservedObject var experience: Experience

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var saveableTimeDisplayStyle: SaveableTimeDisplayStyle = .auto
    @State private var isShowingDeleteConfirmation = false
    @State private var sheetToShow: SheetOption?
    @State private var showsHiddenItems = false
    @State private var timelineTime: Date?
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(TimelineModel.combinesComparableRoutesKey) private var combinesRoutes = false
    @AppStorage(TimelineModel.showsQuantityDetailsKey) private var showsQuantityDetails = true
    @State private var noteReminder: JournalReminderDraft?
    @State private var pendingIngestionMove: IngestionMove.Receipt?
    @AppStorage(PersistenceController.isOpenLastExperienceSiriTipVisibleKey) private var isSiriTipVisible = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var toastViewModel: ToastViewModel

    enum SheetOption: Identifiable, Hashable {
        case editTitle
        case editNotes
        case editLocation(experienceLocation: ExperienceLocation)
        case addLocation
        case addRating
        case addTimedNote
        case reminder
        case editTimedNote(timedNote: TimedNote)
        case editIngestion(ingestion: Ingestion)
        case shareExperience
        case moveIngestions
        // The assistant about this experience, asking the prompt right away if there is one
        case assistant(prompt: String?)

        var id: Self {
            return self
        }
    }

    @available(iOS 16.2, *)
    private func startLiveActivity() {
        Task {
            await ActivityManager.shared.show(experience)
        }
    }

    private func addIngestion() {
        // can't use Navigator as environment object because for some reason this messes up the layout of this screen
        Navigator.shared.showAddIngestionFullScreenCover(startingAt: experience.startTimeForAddedIngestion)
    }


    var body: some View {
        let isCurrent = experience.isCurrent
        let timeDisplayStyle = saveableTimeDisplayStyle.resolved(isCurrent: isCurrent)
        let myIngestions = experience.myIngestionsSorted
        let firstIngestionTime = experience.ingestionsSorted.first?.time
        let timedNotes = experience.timedNotesSorted
        List {
            experienceSummary(ingestions: myIngestions)
            let timelineModel = experience.getMyTimeLineModel(
                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
                combinesComparableRoutes: combinesRoutes
            )
            if timelineModel.isWorthDrawing {
                Section {
                    EffectTimeline(
                        timelineModel: timelineModel,
                        height: 156,
                        timeDisplayStyle: timeDisplayStyle,
                        cursorTime: timelineTime.map(timelineModel.clampingTime),
                        onTimeSelected: { timelineTime = $0 }
                    )
                    if let timelineTime {
                        let selectedTime = timelineModel.clampingTime(timelineTime)
                        LabeledContent("Selected Time") {
                            Text(selectedTime, format: TimelineCursorEntry.dateFormat)
                                .monospacedDigit()
                        }
                        if let estimate = timelineModel.effectEstimate(at: selectedTime) {
                            TimelineEstimateRows(estimate: estimate, time: selectedTime)
                        }
                    } else if isCurrent {
                        TimelineView(.explicit(timelineModel.phaseUpdateDates(from: .now))) { context in
                            if let estimate = timelineModel.effectEstimate(at: context.date) {
                                TimelineEstimateRows(estimate: estimate, time: context.date, showsCountdown: true)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(timelineModel.groupDrawables.contains(where: \.hasDurationInfo) ? "Estimated Effects" : "Timeline")
                        Spacer()
                        timeDisplayMenu
                        expandTimelineLink
                    }
                } footer: {
                    if showsQuantityDetails, let time = timelineTime.map(timelineModel.clampingTime),
                       timelineModel.effectEstimate(at: time)?.curveScaledAmount(at: time) != nil {
                        Text("The curve-scaled amount is the logged amount multiplied by the curve’s relative height.")
                    }
                }
            }
            if HeartRateWindow.isAvailable,
               let window = HeartRateWindow.recorded(in: experience, includesRatings: isEyeOpen) {
                let hasTimeline = timelineModel.isWorthDrawing && timelineModel.totalWidth > 0
                HeartRateTimelineSection(
                    window: window,
                    domain: hasTimeline ? timelineModel.timeRange : nil,
                    cursor: hasTimeline ? timelineTime.map(timelineModel.clampingTime) : timelineTime,
                    selectTime: { timelineTime = $0 }
                )
            }
            Section {
                if experience.ingestionsSorted.contains(where: \.isHiddenFromTimeline)
                    || (isEyeOpen && experience.ratingsWithTimeSorted.contains(where: \.isHiddenInTimeline)) {
                    Button { showsHiddenItems = true } label: {
                        Label("Hidden Items", systemImage: "eye.slash")
                    }
                }
                if !myIngestions.isEmpty || !timedNotes.isEmpty {
                    TimelineSection(
                        timelineModel: nil,
                        editIngestion: { ingestionToEdit in
                            sheetToShow = .editIngestion(ingestion: ingestionToEdit)
                        },
                        ingestionsSorted: myIngestions,
                        timeDisplayStyle: timeDisplayStyle,
                        isEyeOpen: isEyeOpen,
                        isHidingDosageDots: isHidingDosageDots,
                        isCurrentExperience: isCurrent,
                        timedNotes: timedNotes,
                        firstIngestionTimeForNotes: firstIngestionTime,
                        editTimedNote: { sheetToShow = .editTimedNote(timedNote: $0) },
                        remindAboutTimedNote: { note in
                            let date = note.timeUnwrapped > .now ? note.timeUnwrapped : Date.now.addingTimeInterval(3600)
                            noteReminder = JournalReminderDraft(date: date, source: .timedNote)
                        }
                    )
                }
                if #available(iOS 16.2, *) {
                    if !myIngestions.isEmpty, !ProcessInfo.processInfo.isiOSAppOnMac, isCurrent && timelineModel.isWorthDrawing {
                        LiveActivityButton(experience: experience, startLiveActivity: startLiveActivity)
                    }
                }
            } header: {
                HStack {
                    Text("Entries")
                    if !timelineModel.isWorthDrawing {
                        Spacer()
                        timeDisplayMenu
                        if !myIngestions.isEmpty || !timedNotes.isEmpty || (isEyeOpen && !experience.ratingsWithTimeSorted.isEmpty) {
                            expandTimelineLink
                        }
                    }
                }
            } footer: {
                if myIngestions.contains(where: \.isUnconfirmed) {
                    Text("Estimates and totals use confirmed ingestions.")
                }
            }
            if isEyeOpen, !myIngestions.isEmpty {
                let cumulativeDoses = ExperienceLogic.myCumulativeDoses(from: myIngestions)
                if !cumulativeDoses.isEmpty {
                    CumulativeDoseSection(
                        title: "Your Cumulative Dose",
                        cumulativeDoses: cumulativeDoses.sorted { $0.substanceName < $1.substanceName },
                        isHidingDosageDots: isHidingDosageDots,
                        isEyeOpen: isEyeOpen
                    )
                }
            }
            let notes = experience.textUnwrapped
            if !notes.isEmpty {
                Section("Notes") {
                    Button {
                        sheetToShow = .editNotes
                    } label: {
                        Text(notes)
                            .foregroundStyle(.primary)
                            .padding(.vertical, 5)
                    }
                    .accessibilityHint("Edit notes")
                }
            }
            if isEyeOpen && !experience.ratingsUnwrapped.isEmpty {
                ShulginRatingSection(
                    experience: experience,
                    timeDisplayStyle: timeDisplayStyle,
                    firstIngestionTime: firstIngestionTime
                )
            }
            if isEyeOpen && !isHidingToleranceChartInExperience {
                let chartData = experience.chartData
                if !chartData.toleranceWindows.isEmpty {
                    ToleranceChartSection(
                        chartData: chartData,
                        experienceStartDate: experience.sortDateUnwrapped,
                        isTimeRelative: timeDisplayStyle == .relativeToNow
                    )
                }
            }
            if Set(experience.ingestionsSorted.map({ $0.isMine ? "" : $0.consumerNameUnwrapped })).count > 1 {
                Section {
                    NavigationLink {
                        ExperienceTimelineComparison(experience: experience, selectedTime: $timelineTime)
                    } label: {
                        Label("Compare Timelines", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            ForEach(experience.getConsumers(areRedosesDrawnIndividually: areRedosesDrawnIndividually, areSubstanceHeightsIndependent: areSubstanceHeightsIndependent)) { consumer in
                let consumerTimelineModel = consumer.timelineModel
                Section {
                    TimelineSection(
                        timelineModel: consumerTimelineModel,
                        editIngestion: { ingestionToEdit in
                            sheetToShow = .editIngestion(ingestion: ingestionToEdit)
                        },
                        ingestionsSorted: consumer.ingestionsSorted,
                        timeDisplayStyle: timeDisplayStyle,
                        isEyeOpen: isEyeOpen,
                        isHidingDosageDots: isHidingDosageDots,
                        isCurrentExperience: isCurrent
                    )
                } header: {
                    HStack {
                        Text(consumer.consumerName)
                        Spacer()
                        NavigationLink(value: GlobalNavigationDestination.timeline(
                            timelineModel: consumerTimelineModel,
                            timeDisplayStyle: timeDisplayStyle)) {
                                Label("Timeline screen", systemImage: "arrow.down.left.and.arrow.up.right.square").labelStyle(.iconOnly)
                            }
                    }
                }
            }
            if isEyeOpen && !isHidingSubstanceInfoInExperience {
                SubstanceInfoSections(substancesUsed: experience.substancesUsed, interactions: experience.interactions) {
                    if isCurrent {
                        SiriTipView(intent: OpenLastExperienceIntent(), isVisible: $isSiriTipVisible)
                    }
                }
            }
            if let location = experience.location {
                Section {
                    EditLocationLinkAndMap(experienceLocation: location)
                } header: {
                    HStack {
                        Text("Location")
                        Spacer()
                        Button {
                            sheetToShow = .editLocation(experienceLocation: location)
                        } label: {
                            Label("Edit Location", systemImage: "pencil")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .sheet(
            item: $sheetToShow,
            content: { sheet in
                switch sheet {
                case .addLocation:
                    AddLocationScreen(locationManager: locationManager, experience: experience)
                case let .editLocation(experienceLocation):
                    EditLocationScreen(experienceLocation: experienceLocation, locationManager: locationManager)
                case .editNotes:
                    EditNotesScreen(experience: experience)
                case .editTitle:
                    EditTitleScreen(experience: experience)
                case .addRating:
                    AddRatingScreen(experience: experience, canDefineOverall: experience.overallRating == nil)
                case .addTimedNote:
                    AddTimedNoteScreen(experience: experience)
                case .reminder:
                    JournalReminderEditor(draft: JournalReminderDraft())
                case let .editTimedNote(timedNote):
                    EditTimedNoteScreen(timedNote: timedNote, experience: experience)
                case let .editIngestion(ingestion):
                    EditIngestionScreen(ingestion: ingestion)
                case .moveIngestions:
                    MoveIngestionsScreen(source: experience) { pendingIngestionMove = $0 }
                case let .assistant(prompt):
                    AssistantScreen(experience: experience, initialPrompt: prompt)
                case .shareExperience:
                    ExperienceReportScreen(experience: experience, includesRatings: isEyeOpen)
                }
            })
        .navigationTitle(experience.titleUnwrapped)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ExperienceToolbarContent(
                    experience: experience,
                    sheetToShow: $sheetToShow,
                    isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                    canAddIngestion: isCurrent || isEyeOpen || experience.creationDateUnwrapped.distance(to: .now) < 3 * 60 * 60,
                    addIngestion: addIngestion
                )
            }
        }
        .sheet(isPresented: $showsHiddenItems) {
            NavigationStack { HiddenTimelineItemsScreen(experience: experience, includesRatings: isEyeOpen) }
        }
        .sheet(item: $noteReminder) { JournalReminderEditor(draft: $0) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            moveUndoBar
        }
        .observeExperienceTimeline(experience)
        .confirmationDialog(
            "Delete Experience?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
            actions: {
                Button("Delete", role: .destructive) {
                    delete()
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("This will also delete all of its ingestions.")
            }
        )
    }

    @ViewBuilder
    private var moveUndoBar: some View {
        if let pendingIngestionMove {
            HStack {
                Text("Ingestions Moved")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Undo") { undo(pendingIngestionMove) }
                    .buttonStyle(.bordered)
                Button {
                    self.pendingIngestionMove = nil
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading)
            .padding(.trailing, 6)
            .background(.regularMaterial)
        }
    }

    private func undo(_ receipt: IngestionMove.Receipt) {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let restored = try IngestionMove.undo(receipt, in: context)
            IngestionSaving.didSave(restored, newIngestions: [])
            pendingIngestionMove = nil
            toastViewModel.showSuccessToast(message: String(localized: "Move Undone"))
        } catch {
            toastViewModel.showErrorToast(message: error.localizedDescription)
        }
    }

    private var expandTimelineLink: some View {
        NavigationLink {
            ExperienceTimelineScreen(experience: experience, selection: $timelineTime)
        } label: {
            Label("Expand Timeline", systemImage: "arrow.down.left.and.arrow.up.right.square")
                .labelStyle(.iconOnly)
        }
    }

    private var timeDisplayMenu: some View {
        Menu {
            Picker("Time Display", selection: $saveableTimeDisplayStyle) {
                ForEach(SaveableTimeDisplayStyle.allCases) { style in
                    Text(style.text).tag(style)
                }
            }
        } label: {
            Label("Time Display", systemImage: "timer")
                .labelStyle(.iconOnly)
        }
    }

    private func experienceSummary(ingestions: [Ingestion]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(experience.sortDateUnwrapped, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let first = ingestions.first?.timeUnwrapped, let last = ingestions.last?.timeUnwrapped {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    layout {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("First ingestion").font(.caption).foregroundStyle(.secondary)
                            Text(first, format: .dateTime.hour().minute()).font(.headline)
                        }
                        if first != last {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Last ingestion").font(.caption).foregroundStyle(.secondary)
                                Text(last, format: Calendar.current.isDate(first, inSameDayAs: last)
                                    ? .dateTime.hour().minute()
                                    : .dateTime.weekday(.abbreviated).hour().minute()
                                ).font(.headline)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func delete() {
        Task {
            if await IngestionDeletion.delete(experience: experience) {
                dismiss()
            }
        }
    }
}
// swiftlint:enable type_body_length
