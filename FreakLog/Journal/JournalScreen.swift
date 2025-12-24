import SwiftUI

struct JournalScreen: View {

    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    @Binding var isFavoriteFilterEnabled: Bool


    @AppStorage(PersistenceController.timeDisplayStyleKey) private var timeDisplayStyleText: String = SaveableTimeDisplayStyle.auto.rawValue

    private var timeDisplayStyle: SaveableTimeDisplayStyle {
        SaveableTimeDisplayStyle(rawValue: timeDisplayStyleText) ?? .auto
    }

    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPositionString: String = FabButtonPosition.center.rawValue

    var fabAlignment: Alignment {
        (FabButtonPosition(rawValue: fabButtonPositionString) ?? .center).alignment
    }

    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
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
                        timeDisplayStyle: timeDisplayStyle
                    )
                } else {
                    AllIngestionsView(
                        searchText: $searchText,
                        timeDisplayStyle: timeDisplayStyle
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modify {
                let prompt = selectedTab == JournalViewOption.experiences.rawValue ? "Search experiences" : "Search"
                if isSearchPresented {
                    if #available(iOS 17.0, *) {
                        $0.searchable(text: $searchText, isPresented: $isSearchPresented, placement: .automatic, prompt: prompt)
                    } else {
                        $0.searchable(text: $searchText, placement: .automatic, prompt: prompt)
                    }
                } else {
                    $0
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
                HStack {
                    if selectedTab == JournalViewOption.experiences.rawValue {
                        favoriteButton
                    }
                    if !isSearchPresented {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                }
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
            ForEach([SaveableTimeDisplayStyle.auto, .regular, .relativeToNow]) { style in
                Button {
                    timeDisplayStyleText = style.rawValue
                } label: {
                    if timeDisplayStyle == style {
                        Label(style.text, systemImage: "checkmark")
                    } else {
                        Text(style.text)
                    }
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
