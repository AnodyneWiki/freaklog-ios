import SwiftUI

struct AllIngestionsView: View {
    @StateObject private var viewModel = AllIngestionsViewModel()
    @Binding var searchText: String
    var timeDisplayStyle: SaveableTimeDisplayStyle
    
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var areRedosesDrawnIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var areSubstanceHeightsIndependent = true
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey)
    private var dynamicRange = DynamicRangeOption.twentyFourHours

    @State private var ingestionToEdit: Ingestion?
    @State private var hiddenIngestions: [ObjectIdentifier] = []

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
        .onChange(of: dynamicRange) { _ in
            viewModel.updateTimelineIngestions()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                            let style = timeDisplayStyle.resolved(isCurrent: dynamicRange.containsRecent(ingestion.timeUnwrapped))

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
                        openDynamicExperience(ingestions: viewModel.getIngestionsForDynamicExperience(for: ingestion))
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
