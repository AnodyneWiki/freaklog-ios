import SwiftUI

struct JournalScreen: View {

    @Binding var isFavoriteFilterEnabled: Bool

    @State private var journalWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(PersistenceController.timeDisplayStyleKey) private var timeDisplayStyle: SaveableTimeDisplayStyle = .auto
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPosition: FabButtonPosition = .right
    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
    @AppStorage(PersistenceController.defaultJournalViewKey) private var defaultTab: JournalViewOption = .allIngestions
    // The tab switched to in the journal, nil while on the default. It doesn't change the default tab setting.
    @State private var switchedTab: JournalViewOption?
    @State private var isAddingTimedNote = false
    @State private var isShowingAssistant = false
    @ObservedObject private var tabs = TabManager.shared
    @ObservedObject private var routines = RoutineSchedules.shared
    @AppStorage(PersistenceController.showsDueTodayKey) private var showsDueToday = false
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
        } screen: {
            Group {
                if selectedTab == .experiences {
                    ExperiencesList(
                        searchText: "",
                        isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                        timeDisplayStyle: timeDisplayStyle
                    )
                } else {
                    AllIngestionsView(
                        searchText: "",
                        isFavoriteFilterEnabled: isFavoriteFilterEnabled,
                        timeDisplayStyle: timeDisplayStyle,
                        showsTimeline: !isFavoriteFilterEnabled
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if !isHidingJournalTabSwitcher, dynamicTypeSize.isAccessibilitySize {
                        HStack {
                            viewPicker.pickerStyle(.menu)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.bar)
                    }
                    if !showsDirectActions, isFavoriteFilterEnabled {
                        HStack {
                            favoriteButton
                                .labelStyle(.titleAndIcon)
                                .frame(minHeight: 44)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .background(.bar)
                    }
                    if isEyeOpen, showsDueToday, !routines.schedules.isEmpty {
                        NavigationLink(value: GlobalNavigationDestination.dueToday) {
                            HStack {
                                Label("Due Today", systemImage: "calendar.badge.clock")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                        }
                        .background(.bar)
                    }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { journalWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { journalWidth = $0 }
            }
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
            if !isHidingJournalTabSwitcher, !dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .principal) {
                    viewPicker
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 228)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 4) {
                    NavigationLink(value: GlobalNavigationDestination.unifiedSearch) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    if showsDirectActions { favoriteButton }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if showsDirectActions {
                    HStack(spacing: 4) {
                        timeDisplayMenu
                        calendarLink
                        if showsToolsLink {
                            NavigationLink(value: GlobalNavigationDestination.tools) {
                                Label("Tools", systemImage: Tab.tools.icon)
                            }
                        }
                    }
                } else {
                    moreMenu
                }
            }
        }
    }

    private var showsDirectActions: Bool {
        // Leave room for the centered switcher as well as two buttons on each side.
        let minimumWidth: CGFloat = isHidingJournalTabSwitcher ? 320 : 440
        return !dynamicTypeSize.isAccessibilitySize && journalWidth >= minimumWidth + (showsToolsLink ? 44 : 0)
    }

    private var showsToolsLink: Bool { isEyeOpen && tabs.hiddenTabs.contains(.tools) }

    private var calendarLink: some View {
        NavigationLink(value: GlobalNavigationDestination.calendar) {
            Label("Calendar", systemImage: "calendar")
        }
    }

    private var viewPicker: some View {
        Picker("Journal View", selection: selectedTabBinding) {
            ForEach(JournalViewOption.allCases) { option in
                Text(option.text).tag(option)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                isAddingTimedNote = true
            } label: {
                Label("Add Timed Note", systemImage: "note.text")
            }
            Button {
                Navigator.shared.openInCurrentTab(.calendar)
            } label: {
                Label("Calendar", systemImage: "calendar")
            }
            if showsToolsLink {
                Button {
                    Navigator.shared.openInCurrentTab(.tools)
                } label: {
                    Label("Tools", systemImage: Tab.tools.icon)
                }
            }
            favoriteButton
            timeDisplayMenu
        } label: {
            Label("More", systemImage: "ellipsis.circle")
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

    private var favoriteButton: some View {
        Button {
            isFavoriteFilterEnabled.toggle()
        } label: {
            Label("Favorites", systemImage: isFavoriteFilterEnabled ? "star.fill" : "star")
        }
        .accessibilityAddTraits(isFavoriteFilterEnabled ? .isSelected : [])
    }
}

struct JournalEmptyState: View {
    let message: String
    let offersLogging: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(message).foregroundStyle(.secondary)
            if offersLogging {
                Button("Log an Ingestion") {
                    Navigator.shared.showAddIngestionFullScreenCover()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

extension View {
    func modify<Content>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
