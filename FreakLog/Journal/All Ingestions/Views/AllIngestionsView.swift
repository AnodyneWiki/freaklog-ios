import SwiftUI

struct AllIngestionsView: View {
    @StateObject private var viewModel = AllIngestionsViewModel()
    @Binding var searchText: String
    
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var isHidingDosageDots = false

    @State private var ingestionToEdit: Ingestion?
    @State private var hiddenIngestions: [ObjectIdentifier] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Buffer to allow the first header to distinguish between 'naturally at top' and 'pinned'
                Color.clear.frame(height: 12)
                
                ForEach(viewModel.sections) { section in
                    Section(header: ChameleonHeader(title: section.id, date: section.date)) {
                        sectionContent(section)
                    }
                }
                
                loadingIndicator
            }
        }
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
            Button {
                ingestionToEdit = ingestion
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
