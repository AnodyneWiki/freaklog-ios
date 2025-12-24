import SwiftUI

struct JournalScreen: View {

    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    @Binding var isFavoriteFilterEnabled: Bool

    @State private var isTimeRelative = false

    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPositionString: String = FabButtonPosition.center.rawValue

    var fabAlignment: Alignment {
        (FabButtonPosition(rawValue: fabButtonPositionString) ?? .center).alignment
    }

    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = true
    @AppStorage(PersistenceController.defaultJournalViewKey) var selectedTab: Int = JournalViewOption.allIngestions.rawValue

    var body: some View {
        FabPosition(alignment: fabAlignment) {
            if !isSearchPresented {
                Button {
                    Navigator.shared.showAddIngestionFullScreenCover()
                } label: {
                    Label("New Ingestion", systemImage: "plus").labelStyle(FabLabelStyle())
                }
            }
        } screen: {
            Group {
                if selectedTab == JournalViewOption.experiences.rawValue {
                    ExperiencesList(
                        searchText: searchText,
                        isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                        isTimeRelative: isTimeRelative
                    )
                } else {
                    AllIngestionsView(
                        searchText: $searchText,
                        isTimeRelative: isTimeRelative
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modify {
                let prompt = selectedTab == JournalViewOption.experiences.rawValue ? "Search experiences" : "Search"
                if #available(iOS 17.0, *) {
                    $0.searchable(text: $searchText, isPresented: $isSearchPresented, placement: .navigationBarDrawer, prompt: prompt)
                } else {
                    $0.searchable(text: $searchText, placement: .navigationBarDrawer, prompt: prompt)
                }
            }
            .disableAutocorrection(true)
        }
        .navigationTitle("Journal")
        .toolbar {
            if !isHidingJournalTabSwitcher {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $selectedTab) {
                        ForEach(JournalViewOption.allCases) { option in
                            Text(option.text).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                favoriteButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    timeDisplayMenu
                    calendarLink
                }
            }
        }
    }

    private var timeDisplayMenu: some View {
        Menu {
            Button {
                isTimeRelative = false
            } label: {
                let option = SaveableTimeDisplayStyle.regular
                if isTimeRelative {
                    Text(option.text)
                } else {
                    Label(option.text, systemImage: "checkmark")
                }
            }
            Button {
                isTimeRelative = true
            } label: {
                let option = SaveableTimeDisplayStyle.relativeToNow
                if isTimeRelative {
                    Label(option.text, systemImage: "checkmark")
                } else {
                    Text(option.text)
                }
            }
        } label: {
            Label("Time Display", systemImage: "timer")
        }
    }

    private var calendarLink: some View {
        NavigationLink(value: GlobalNavigationDestination.calendar) {
            Label("Calendar", systemImage: "calendar")
        }
    }

    private var favoriteButton: some View {
        Button {
            isFavoriteFilterEnabled.toggle()
        } label: {
            if isFavoriteFilterEnabled {
                Label("Don't Filter Favorites", systemImage: "star.fill")
            } else {
                Label("Filter Favorites", systemImage: "star")
            }
        }
    }
}

extension View {
    func modify<Content>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
