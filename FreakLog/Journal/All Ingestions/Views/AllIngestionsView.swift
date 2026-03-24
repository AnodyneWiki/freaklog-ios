import SwiftUI

struct AllIngestionsView: View {
    @StateObject private var viewModel = AllIngestionsViewModel()
    @Binding var searchText: String
    var timeDisplayStyle: SaveableTimeDisplayStyle
    
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var areRedosesDrawnIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var areSubstanceHeightsIndependent = true
    @AppStorage(PersistenceController.timeDisplayStyleKey) private var timeDisplayStyleText: String = SaveableTimeDisplayStyle.auto.rawValue
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) private var dynamicExperienceRangeHours: Int = 24

    @State private var ingestionToEdit: Ingestion?
    @State private var hiddenIngestions: [ObjectIdentifier] = []
    @State private var pinnedDates: Set<Date> = []

    var body: some View {
        VStack(spacing: 0) {
            timelineSection
            
            List {
                ForEach(viewModel.sections) { section in
                    Section(header: ChameleonHeader(
                        title: section.id,
                        date: section.date,
                        dynamicExperienceDestination: {
                            let dynamicIngestions = viewModel.getIngestionsForDynamicExperienceLastIngestion(for: section.date)
                            if !dynamicIngestions.isEmpty {
                                return GlobalNavigationDestination.dynamicExperience(ingestions: dynamicIngestions)
                            }
                            return nil
                        }(),
                        onPinnedStateChanged: { isPinned in
                            if isPinned {
                                pinnedDates.insert(section.date)
                            } else {
                                pinnedDates.remove(section.date)
                            }
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
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "scroll")
        .sheet(item: $ingestionToEdit) { ingestion in
            let isHidden = Binding(
                get: { hiddenIngestions.contains(ingestion.id) },
                set: { newIsHidden in
                    if newIsHidden {
                        hiddenIngestions.append(ingestion.id)
                    } else {
                        hiddenIngestions.removeAll { $0 == ingestion.id }
                    }
                }
            )
            EditIngestionScreen(
                ingestion: ingestion,
                isHidden: isHidden
            )
        }
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
        .onAppear {
            if viewModel.searchText != searchText {
                viewModel.searchText = searchText
            }
            viewModel.updateTimelineIngestions()
        }
        .onChange(of: dynamicExperienceRangeHours) { _ in
            viewModel.updateTimelineIngestions()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
    }

    private var viewTimeDisplayStyle: TimeDisplayStyle {
        switch timeDisplayStyle {
        case .regular: return .regular
        case .relativeToNow: return .relativeToNow
        case .relativeToStart: return .relativeToStart
        case .between: return .between
        case .auto: return .regular // In general list, auto usually means regular
        }
    }

    private var timelineModel: ChartTimelineModel {
        // Determine the "active" date based on scrolling
        // IF scrolling down (newest to oldest), the visible pinned header is likely the minimal date in the pinned set
        // (because older dates are smaller/eaerlier, and they come "after" newer dates in the list, so they pin last).
        // Wait:
        // Newest (Today) -> Pins. Set={Today}. Min=Today.
        // Scroll down -> Yesterday (Older) -> Pins. Set={Today, Yesterday}. Min=Yesterday.
        // Scroll down -> DayBefore (Even Older) -> Pins. Set={... DayBefore}. Min=DayBefore.
        // This logic holds for Reverse Chronological lists.
        
        let anchorDate: Date = {
            if let minPinned = pinnedDates.min() {
                return minPinned
            }
            // Fallback to first section (newest) or today
            return viewModel.sections.first?.date ?? Date()
        }()
    
        // Use the chameleon header logic to get the range
        // "viewModel.getIngestionsForDynamicExperienceLastIngestion(for: section.date)"
        let ingestionsForChart = viewModel.getIngestionsForDynamicExperienceLastIngestion(for: anchorDate)
        
        // If no ingestions found (empty day?), fallback to something safe or empty
        let chartIngestions = ingestionsForChart.isEmpty ? viewModel.timelineIngestions : ingestionsForChart // Fallback? Or just empty?
        // Actually, if we are on a section with no dynamic context, maybe show nothing or daily?
        // But the section exists, so it must have ingestions.
        
        // Calculate Visible Range based on these ingestions/dynamic range logic
        // The dynamic range logic is embedded in `getIngestions ...`.
        // We need to construct the model from these ingestions.
        
        // We probably want the time range to match the retrieved ingestions + margin?
        // `ExperienceLogic.chartTimelineModel` calculates start time based on the ingestions passed.
        // But we might want to enforce the specific 24h (or dynamic) window.
        
        let anchorTime = chartIngestions.map(\.timeUnwrapped).max() ?? Date()
        let rangeSeconds = TimeInterval(dynamicExperienceRangeHours * 60 * 60)
        let startTime = anchorTime.addingTimeInterval(-rangeSeconds)
        let visibleRange = startTime...anchorTime

        return ExperienceLogic.chartTimelineModel(
            from: chartIngestions,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            visibleTimeRange: visibleRange
        )
    }
}

// MARK: - Subviews

private extension AllIngestionsView {

    @ViewBuilder
    var timelineSection: some View {
        if timelineModel.isWorthDrawing {
            Button {
                 Navigator.shared.journalTabPath.append(GlobalNavigationDestination.dynamicExperience(ingestions: viewModel.timelineIngestions))
            } label: {
                VStack(spacing: 0) {
                    ChartTimelineView(
                        timelineModel: timelineModel,
                        height: 200,
                        isShowingCurrentTime: true
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
        ForEach(section.ingestions) { ingestion in
            VStack(spacing: 0) {
                Button {
                    ingestionToEdit = ingestion
                } label: {
                    IngestionRow(
                        ingestion: ingestion,
                        isEyeOpen: isEyeOpen,
                        isHidingDosageDots: isHidingDosageDots,
                        timeText: {
                            let style: TimeDisplayStyle = {
                                switch timeDisplayStyle {
                                case .regular: return .regular
                                case .relativeToNow: return .relativeToNow
                                case .relativeToStart: return .relativeToStart
                                case .between: return .between
                                case .auto:
                                    // Auto logic: relative if recent (within dynamic range), otherwise regular
                                    let window = TimeInterval(dynamicExperienceRangeHours) * 60 * 60
                                    if ingestion.timeUnwrapped > Date.now.addingTimeInterval(-window) {
                                        return .relativeToNow
                                    } else {
                                        return .regular
                                    }
                                }
                            }()
                            
                            if style == .relativeToNow {
                                if timeDisplayStyle == .auto {
                                    HStack(spacing: 0) {
                                        Text(ingestion.timeUnwrapped, style: .time)
                                        Text(" (")
                                        RelativeTimeText(date: ingestion.timeUnwrapped)
                                        Text(")")
                                    }
                                } else {
                                    RelativeTimeText(date: ingestion.timeUnwrapped)
                                }
                            } else {
                                Text(ingestion.timeUnwrapped, style: .time)
                            }
                        }
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(Color(UIColor.systemBackground))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        let relatedIngestions = viewModel.getIngestionsForDynamicExperience(for: ingestion)
                        if !relatedIngestions.isEmpty {
                            Navigator.shared.journalTabPath.append(GlobalNavigationDestination.dynamicExperience(ingestions: relatedIngestions))
                        }
                    } label: {
                        Label("Overview", systemImage: "clock.arrow.circlepath")
                    }

                    if let experience = ingestion.experience {
                        Button {
                            Navigator.shared.journalTabPath.append(GlobalNavigationDestination.experience(experience: experience))
                        } label: {
                            Label("Open Experience", systemImage: "person.text.rectangle")
                        }
                    }
                    
                    Button {
                        ingestionToEdit = ingestion
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        viewModel.delete(ingestion)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                if ingestion != section.ingestions.last {
                    Divider()
                        .padding(.leading, 56)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    viewModel.delete(ingestion)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
