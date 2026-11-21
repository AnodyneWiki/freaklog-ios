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
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPosition: FabButtonPosition = .center

    @Environment(\.dismiss) var dismiss
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

        var id: Self {
            return self
        }
    }

    func updateActivityIfActive() {
        guard #available(iOS 16.2, *), LiveActivities.areAvailable, ActivityManager.shared.isActivityActive else { return }
        if let lastTime = experience.myIngestionsSorted.last?.time, lastTime > Date.now.addingTimeInterval(-12 * 60 * 60) {
            startOrUpdateLiveActivity()
        }
    }

    private var liveActivityState: TimelineWidgetAttributes.ContentState {
        experience.liveActivityState(
            hiddenIngestions: hiddenIngestions,
            hiddenRatings: hiddenRatings,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
    }

    @available(iOS 16.2, *)
    func startOrUpdateLiveActivity() {
        let state = liveActivityState
        Task {
            await ActivityManager.shared.startOrUpdateActivity(state)
        }
    }

    @available(iOS 16.2, *)
    func stopLiveActivity() {
        let state = liveActivityState
        Task {
            await ActivityManager.shared.stopActivity(state)
        }
    }

    private func addIngestion() {
        UserDefaults.standard.set(experience.ingestionsSorted.last?.time?.timeIntervalSince1970, forKey: PersistenceController.lastIngestionTimeOfExperienceWhereAddIngestionTappedKey)
        Navigator.shared.showAddIngestionFullScreenCover() // can't use Navigator as environment object because for some reason this messes up the layout of this screen
    }


    var body: some View {
        let isCurrent = experience.isCurrent
        let timeDisplayStyle = saveableTimeDisplayStyle.resolved(isCurrent: isCurrent)
        let myIngestions = experience.myIngestionsSorted
        let firstIngestionTime = experience.ingestionsSorted.first?.time
        FabPosition(alignment: fabButtonPosition.alignment) {
            let threeHours: TimeInterval = 3*60*60
            if isCurrent || experience.creationDateUnwrapped.distance(to: .now) < threeHours {
                Button(action: addIngestion) {
                    Label("New Ingestion", systemImage: "plus").labelStyle(FabLabelStyle())
                }
            }
        } screen: {
            List {
                if !myIngestions.isEmpty {
                    let timelineModel = experience.getMyTimeLineModel(
                        hiddenIngestions: hiddenIngestions,
                        hiddenRatings: hiddenRatings,
                        areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                        areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                    )
                    Section {
                        TimelineSection(
                            timelineModel: timelineModel,
                            editIngestion: { ingestionToEdit in
                                sheetToShow = .editIngestion(ingestion: ingestionToEdit)
                            },
                            ingestionsSorted: myIngestions,
                            timeDisplayStyle: timeDisplayStyle,
                            isEyeOpen: isEyeOpen,
                            isHidingDosageDots: isHidingDosageDots,
                            hiddenIngestions: hiddenIngestions,
                            isCurrentExperience: isCurrent
                        )
                        if #available(iOS 16.2, *) {
                            // The button itself follows whether the user allows live activities
                            if !ProcessInfo.processInfo.isiOSAppOnMac, isCurrent && timelineModel.isWorthDrawing {
                                LiveActivityButton(
                                    stopLiveActivity: {
                                        stopLiveActivity()
                                    },
                                    startLiveActivity: {
                                        startOrUpdateLiveActivity()
                                    }
                                )
                            }
                        }
                    } header: {
                        HStack {
                            Text(experience.sortDateUnwrapped, format: Date.FormatStyle().day().month().year().weekday(.abbreviated))
                            Spacer()
                            NavigationLink(value: GlobalNavigationDestination.timeline(
                                timelineModel: timelineModel,
                                timeDisplayStyle: timeDisplayStyle)) {
                                    Label("Timeline screen", systemImage: "arrow.down.left.and.arrow.up.right.square").labelStyle(.iconOnly)
                                }
                        }
                    }
                    if isEyeOpen {
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
                let timedNotesSorted = experience.timedNotesSorted
                if !timedNotesSorted.isEmpty {
                    Section("Timed Notes") {
                        ForEach(Array(timedNotesSorted.enumerated()), id: \.element) { index, timedNote in
                            let previousNote = timedNotesSorted[safe: index - 1]
                            Button(action: {
                                sheetToShow = .editTimedNote(timedNote: timedNote)
                            }, label: {
                                TimedNoteRow(timedNote: timedNote) {
                                    EventTimeText(
                                        time: timedNote.timeUnwrapped,
                                        style: timeDisplayStyle,
                                        firstIngestionTime: firstIngestionTime,
                                        previousTime: previousNote?.timeUnwrapped
                                    )
                                }.foregroundColor(.primary) // to override the button styles
                            })
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
                onDismiss: {
                    updateActivityIfActive()
                },
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
                    }
                })
        }
        .navigationTitle(experience.titleUnwrapped)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ExperienceToolbarContent(
                    experience: experience,
                    saveableTimeDisplayStyle: $saveableTimeDisplayStyle,
                    sheetToShow: $sheetToShow,
                    isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                    addIngestion: addIngestion
                )
            }
        }
        // Hiding ingestions or ratings also hides them in the live activity
        .onChange(of: hiddenIngestions) { _ in updateActivityIfActive() }
        .onChange(of: hiddenRatings) { _ in updateActivityIfActive() }
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

    private func delete() {
        Task {
            await IngestionDeletion.delete(experience: experience)
            dismiss()
        }
    }
}
// swiftlint:enable type_body_length
