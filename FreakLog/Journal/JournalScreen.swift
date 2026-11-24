import SwiftUI

struct JournalScreen: View {

    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    @Binding var isFavoriteFilterEnabled: Bool


    @AppStorage(PersistenceController.timeDisplayStyleKey) private var timeDisplayStyle: SaveableTimeDisplayStyle = .auto
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPosition: FabButtonPosition = .right
    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
    @AppStorage(PersistenceController.defaultJournalViewKey) private var defaultTab: JournalViewOption = .allIngestions
    // The tab switched to in the journal, nil while on the default. It doesn't change the default tab setting.
    @State private var switchedTab: JournalViewOption?
    // The experience list builds a new fetch for each search, so it only follows the text once typing pauses
    @State private var experienceSearchText = ""
    @State private var isAddingTimedNote = false
    @State private var isShowingAssistant = false
    @AppStorage(PersistenceController.isAssistantEnabledKey) private var isAssistantEnabled = false

    // Without the switcher there is no way to change tabs, so the default tab is shown
    private var selectedTab: JournalViewOption {
        isHidingJournalTabSwitcher ? defaultTab : switchedTab ?? defaultTab
    }

    private var selectedTabBinding: Binding<JournalViewOption> {
        Binding(get: { selectedTab }, set: { switchedTab = $0 })
    }

    var body: some View {
        FabPosition(alignment: fabButtonPosition.alignment) {
            if !isSearchPresented {
                VStack(spacing: 12) {
                    if isAssistantEnabled {
                        Button {
                            isShowingAssistant = true
                        } label: {
                            Label("Assistant", systemImage: "text.bubble")
                                .labelStyle(FabLabelStyle(isSecondary: true))
                        }
                        .buttonStyle(.plain)
                    }
                    AddFabButton {
                        Navigator.shared.showAddIngestionFullScreenCover()
                    } addTimedNote: {
                        isAddingTimedNote = true
                    }
                }
            }
        } screen: {
            Group {
                if selectedTab == .experiences {
                    ExperiencesList(
                        searchText: experienceSearchText,
                        isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                        timeDisplayStyle: timeDisplayStyle
                    )
                } else {
                    AllIngestionsView(
                        searchText: searchText,
                        isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                        timeDisplayStyle: timeDisplayStyle
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: searchText) {
                if !searchText.isEmpty {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                }
                experienceSearchText = searchText
            }
            .modify {
                let prompt = selectedTab == .experiences ? "Search experiences" : "Search ingestions"
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
        // Both tabs share one inline bar, so switching doesn't resize it; the switcher takes the title's place
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: defaultTab) { _ in
            switchedTab = nil
        }
        .sheet(isPresented: $isAddingTimedNote) {
            AddTimedNoteScreen(experience: nil)
        }
        .sheet(isPresented: $isShowingAssistant) {
            AssistantScreen(experience: nil, suggestsCurrentSessionSummary: selectedTab == .allIngestions)
        }
        .toolbar {
            if !isHidingJournalTabSwitcher {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: selectedTabBinding) {
                        ForEach(JournalViewOption.allCases) { option in
                            Text(option.text).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 8) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    favoriteButton
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
                    timeDisplayStyle = style
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
