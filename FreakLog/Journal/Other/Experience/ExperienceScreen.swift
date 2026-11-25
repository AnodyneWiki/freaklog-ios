import SwiftUI
import AppIntents

// swiftlint:disable type_body_length
struct ExperienceScreen: View {
    @ObservedObject var experience: Experience

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var saveableTimeDisplayStyle: SaveableTimeDisplayStyle = .auto
    @State private var isShowingDeleteConfirmation = false
    @State private var sheetToShow: SheetOption?
    @State private var hiddenIngestions: Set<ObjectIdentifier> = []
    @State private var hiddenRatings: Set<ObjectIdentifier> = []
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(PersistenceController.isOpenLastExperienceSiriTipVisibleKey) private var isSiriTipVisible = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var locationManager: LocationManager

    enum SheetOption: Identifiable, Hashable {
        case editTitle
        case editNotes
        case editLocation(experienceLocation: ExperienceLocation)
        case addLocation
        case addRating
        case addTimedNote
        case editTimedNote(timedNote: TimedNote)
        case editIngestion(ingestion: Ingestion)
        case shareExperience
        // The assistant about this experience, asking the prompt right away if there is one
        case assistant(prompt: String?)

        var id: Self {
            return self
        }
    }

    @available(iOS 16.2, *)
    private func startLiveActivity() {
        Task {
            await ActivityManager.shared.show(experience, hiddenIngestions: hiddenIngestions, hiddenRatings: hiddenRatings)
        }
    }

    // Hiding ingestions or ratings also hides them in the live activity
    private func updateLiveActivityHiddenItems() {
        guard #available(iOS 16.2, *) else { return }
        ActivityManager.shared.setHidden(ingestions: hiddenIngestions, ratings: hiddenRatings, in: experience)
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
                hiddenIngestions: hiddenIngestions,
                hiddenRatings: hiddenRatings,
                areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
            )
            if timelineModel.isWorthDrawing {
                Section {
                    EffectTimeline(timelineModel: timelineModel, height: 156, timeDisplayStyle: timeDisplayStyle)
                } header: {
                    HStack {
                        Text(timelineModel.groupDrawables.contains(where: \.hasDurationInfo) ? "Estimated Effects" : "Timeline")
                        Spacer()
                        timeDisplayMenu
                        NavigationLink(value: GlobalNavigationDestination.timeline(
                            timelineModel: timelineModel,
                            timeDisplayStyle: timeDisplayStyle)) {
                            Label("Expand Timeline", systemImage: "arrow.down.left.and.arrow.up.right.square")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            Section {
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
                        hiddenIngestions: hiddenIngestions,
                        isCurrentExperience: isCurrent,
                        timedNotes: timedNotes,
                        firstIngestionTimeForNotes: firstIngestionTime,
                        editTimedNote: { sheetToShow = .editTimedNote(timedNote: $0) }
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
                    }
                }
            }
            if ExperienceHeartRateScreen.isAvailable,
               let window = ExperienceHeartRateScreen.window(for: experience, includesRatings: isEyeOpen) {
                Section("Measured Data") {
                    NavigationLink {
                        ExperienceHeartRateScreen(window: window)
                    } label: {
                        Label("Heart Rate", systemImage: "heart")
                    }
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
                    Text(notes)
                        .padding(.vertical, 5)
                        .onTapGesture {
                            sheetToShow = .editNotes
                        }
                }
            }
            if isEyeOpen && !experience.ratingsUnwrapped.isEmpty {
                ShulginRatingSection(
                    experience: experience,
                    hiddenRatings: $hiddenRatings,
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
            ForEach(experience.getConsumers(hiddenIngestions: hiddenIngestions, areRedosesDrawnIndividually: areRedosesDrawnIndividually, areSubstanceHeightsIndependent: areSubstanceHeightsIndependent)) { consumer in
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
                        hiddenIngestions: hiddenIngestions,
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
                case let .editTimedNote(timedNote):
                    EditTimedNoteScreen(timedNote: timedNote, experience: experience)
                case let .editIngestion(ingestion):
                    EditIngestionScreen(
                        ingestion: ingestion,
                        isHidden: $hiddenIngestions.contains(ingestion.id))
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
        .onChange(of: hiddenIngestions) { _ in updateLiveActivityHiddenItems() }
        .onChange(of: hiddenRatings) { _ in updateLiveActivityHiddenItems() }
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
