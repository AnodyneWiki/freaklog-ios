import SwiftUI

struct AllIngestionsView: View {
    @StateObject private var viewModel = AllIngestionsViewModel()
    let searchText: String
    let isFavoriteFilterEnabled: Bool
    var timeDisplayStyle: SaveableTimeDisplayStyle
    
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var areRedosesDrawnIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var areSubstanceHeightsIndependent = true
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey)
    private var dynamicRange = DynamicRangeOption.twentyFourHours

    @State private var sheetToShow: SheetOption?
    @State private var hiddenIngestions: Set<ObjectIdentifier> = []

    var body: some View {
        List {
            timelineSection
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            ForEach(viewModel.sections) { section in
                Section(header: ChameleonHeader(
                    title: section.id,
                    date: section.date,
                    onOverview: {
                        let ingestions = viewModel.getIngestionsForDynamicExperienceLastIngestion(for: section.date)
                        openDynamicExperience(ingestions: ingestions)
                    }
                )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                ) {
                    sectionContent(section)
                }
                .textCase(nil) // Prevent default header capitalization
            }
            
            loadingIndicator
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.sections.isEmpty && viewModel.hasReachedEnd {
                Text(emptyText)
                    .foregroundColor(.secondary)
            }
        }
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "scroll")
        .sheet(item: $sheetToShow) { sheet in
            switch sheet {
            case .editIngestion(let ingestion):
                EditIngestionScreen(
                    ingestion: ingestion,
                    isHidden: $hiddenIngestions.contains(ingestion.id)
                )
            case .editTimedNote(let timedNote, let experience):
                EditTimedNoteScreen(timedNote: timedNote, experience: experience)
            }
        }
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
        .onChange(of: isFavoriteFilterEnabled) { newValue in
            viewModel.isFavoriteFilterEnabled = newValue
        }
        .onAppear {
            if viewModel.searchText != searchText {
                viewModel.searchText = searchText
            }
            if viewModel.isFavoriteFilterEnabled != isFavoriteFilterEnabled {
                viewModel.isFavoriteFilterEnabled = isFavoriteFilterEnabled
            }
            viewModel.updateTimelineIngestions()
        }
        .onChange(of: dynamicRange) { _ in
            viewModel.updateTimelineIngestions()
        }
    }

    // The same messages as the experience list
    private var emptyText: String {
        switch (searchText.isEmpty, isFavoriteFilterEnabled) {
        case (false, true): "No favorites match the search"
        case (false, false): "No ingestions match the search"
        case (true, true): "No ingestions in favorite experiences"
        case (true, false): "No ingestions yet"
        }
    }

    // In the general list, auto means regular time for the timeline
    private var viewTimeDisplayStyle: TimeDisplayStyle {
        timeDisplayStyle.resolved(isCurrent: false)
    }

    private var timelineModel: TimelineModel {
        ExperienceLogic.dynamicTimelineModel(
            from: viewModel.timelineIngestions,
            range: dynamicRange,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
    }

    private enum SheetOption: Identifiable {
        case editIngestion(Ingestion)
        case editTimedNote(TimedNote, experience: Experience)

        var id: ObjectIdentifier {
            switch self {
            case .editIngestion(let ingestion): ingestion.id
            case .editTimedNote(let timedNote, _): timedNote.id
            }
        }
    }

    private func openDynamicExperience(ingestions: [Ingestion]) {
        guard !ingestions.isEmpty else { return }
        Navigator.shared.journalTabPath.append(GlobalNavigationDestination.dynamicExperience(ingestions: ingestions))
    }
}

// MARK: - Subviews

private extension AllIngestionsView {

    @ViewBuilder
    var timelineSection: some View {
        let timelineModel = timelineModel
        if timelineModel.isWorthDrawing {
            Button {
                openDynamicExperience(ingestions: viewModel.timelineIngestions)
            } label: {
                VStack(spacing: 0) {
                    EffectTimeline(
                        timelineModel: timelineModel,
                        height: 200,
                        timeDisplayStyle: viewTimeDisplayStyle,
                        isShowingTopLabels: false
                    )
                    .padding(.top, 8)
                    
                    Divider()
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    func sectionContent(_ section: IngestionSection) -> some View {
        ForEach(section.items) { item in
            VStack(spacing: 0) {
                switch item {
                case .ingestion(let ingestion):
                    ingestionRow(ingestion)
                case .timedNote(let timedNote):
                    timedNoteRow(timedNote)
                }

                if item.id != section.items.last?.id {
                    Divider()
                        .padding(.leading, 56)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .modifier(SubstanceInfoSwipeAction(substanceName: item.substanceName ?? ""))
        }
    }

    func ingestionRow(_ ingestion: Ingestion) -> some View {
        Button {
            sheetToShow = .editIngestion(ingestion)
        } label: {
            IngestionRow(
                ingestion: ingestion,
                isEyeOpen: isEyeOpen,
                isHidingDosageDots: isHidingDosageDots,
                timeText: { timeText(for: ingestion.timeUnwrapped) }
            )
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                openDynamicExperience(ingestions: viewModel.getIngestionsForDynamicExperience(for: ingestion))
            } label: {
                Label("Overview", systemImage: "clock.arrow.circlepath")
            }

            if let experience = ingestion.experience {
                openExperienceButton(experience)
            }

            Button {
                sheetToShow = .editIngestion(ingestion)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                viewModel.delete(ingestion)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func timedNoteRow(_ timedNote: TimedNote) -> some View {
        Button {
            editTimedNote(timedNote)
        } label: {
            TimedNoteRow(timedNote: timedNote) {
                timeText(for: timedNote.timeUnwrapped)
            }
            .foregroundColor(.primary) // to override the button styles
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let experience = timedNote.experience {
                openExperienceButton(experience)
            }

            Button {
                editTimedNote(timedNote)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                viewModel.delete(timedNote)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func openExperienceButton(_ experience: Experience) -> some View {
        Button {
            Navigator.shared.journalTabPath.append(GlobalNavigationDestination.experience(experience: experience))
        } label: {
            Label("Open Experience", systemImage: "person.text.rectangle")
        }
    }

    func editTimedNote(_ timedNote: TimedNote) {
        guard let experience = timedNote.experience else { return }
        sheetToShow = .editTimedNote(timedNote, experience: experience)
    }

    func delete(_ item: IngestionSection.Item) {
        switch item {
        case .ingestion(let ingestion): viewModel.delete(ingestion)
        case .timedNote(let timedNote): viewModel.delete(timedNote)
        }
    }

    // Recent events are shown relative to now under the auto style, with their clock time
    @ViewBuilder
    func timeText(for time: Date) -> some View {
        let style = timeDisplayStyle.resolved(isCurrent: dynamicRange.containsRecent(time))
        if style == .relativeToNow {
            if timeDisplayStyle == .auto {
                HStack(spacing: 0) {
                    Text(time, style: .time)
                    Text(" (")
                    RelativeTimeText(date: time)
                    Text(")")
                }
            } else {
                RelativeTimeText(date: time)
            }
        } else {
            Text(time, style: .time)
        }
    }

    @ViewBuilder
    var loadingIndicator: some View {
        if !viewModel.hasReachedEnd {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .onAppear {
                    viewModel.fetchNextBatch()
                }
        }
    }
}
