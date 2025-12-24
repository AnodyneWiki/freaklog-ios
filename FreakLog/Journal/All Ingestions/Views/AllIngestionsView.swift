import SwiftUI

struct AllIngestionsView: View {
    @StateObject private var viewModel = AllIngestionsViewModel()
    @Binding var searchText: String
    
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false

    @State private var ingestionToEdit: Ingestion?
    @State private var hiddenIngestions: [ObjectIdentifier] = []

    var body: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(header: ChameleonHeader(title: section.id, date: section.date)
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
    }
}

// MARK: - Subviews

private extension AllIngestionsView {
    
    @ViewBuilder
    func sectionContent(_ section: IngestionSection) -> some View {
        ForEach(section.ingestions) { ingestion in
            VStack(spacing: 0) {
                Button {
                    let relatedIngestions = viewModel.getIngestionsForDynamicExperience(for: ingestion)
                    if !relatedIngestions.isEmpty {
                        Navigator.shared.journalTabPath.append(GlobalNavigationDestination.dynamicExperience(ingestions: relatedIngestions))
                    }
                } label: {
                    IngestionRow(
                        ingestion: ingestion,
                        isEyeOpen: isEyeOpen,
                        isHidingDosageDots: isHidingDosageDots,
                        timeText: {
                            Text(ingestion.timeUnwrapped, style: .time)
                        }
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(Color(UIColor.systemBackground))
                }
                .buttonStyle(.plain)
                
                if ingestion != section.ingestions.last {
                    Divider()
                        .padding(.leading, 56)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    ingestionToEdit = ingestion
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
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
