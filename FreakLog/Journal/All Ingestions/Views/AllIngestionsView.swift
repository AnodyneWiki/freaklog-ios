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

    var body: some View {
        List {
            timelineSection
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

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
                    }()
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
            viewModel.searchText = searchText
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private var timelineModel: TimelineModel {
        ExperienceLogic.timelineModel(
            from: viewModel.timelineIngestions,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
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
