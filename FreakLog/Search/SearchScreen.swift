import AppIntents
import CoreData
import SwiftUI
import WrappingHStack

enum UnifiedSearchScope: String, CaseIterable, Identifiable {
    case all, journal, library

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .journal: "Journal"
        case .library: "Library"
        }
    }

    var includesJournal: Bool { self == .journal || self == .all }
    var includesLibrary: Bool { self == .library || self == .all }
}

struct JournalSearchScreen: View {
    @ObservedObject private var navigator = Navigator.shared
    @State private var searchText = ""
    @State private var scope = UnifiedSearchScope.all
    @State private var isSearchPresented = false
    @State private var focusedInitially = false

    var body: some View {
        SearchScreen(
            searchText: $searchText, scope: $scope, isSearchPresented: $isSearchPresented,
            favoritesOnly: $navigator.isFavoriteFilterEnabled, startsInJournal: true
        )
        .task {
            if !focusedInitially {
                focusedInitially = true
                await Task.yield()
                guard !Task.isCancelled else { return }
                isSearchPresented = true
            }
        }
    }
}

struct SearchScreen: View {
    @Binding var searchText: String
    @Binding var scope: UnifiedSearchScope
    @Binding var isSearchPresented: Bool
    @Binding var favoritesOnly: Bool
    var startsInJournal = false

    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(PersistenceController.isSearchSubstanceSiriTipVisibleKey) private var isSiriTipVisible = false
    @State private var filters = UnifiedSearchFilters()
    @State private var isShowingFilters = false
    @State private var isShowingAddCustomSubstance = false
    @State private var ingestionToEdit: Ingestion?
    @State private var noteToEdit: TimedNote?
    @State private var appliedText = ""
    @State private var resultLimit = 50

    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>

    @FetchRequest(fetchRequest: PersistenceController.substanceOverridesRequest())
    private var overrides: FetchedResults<SubstanceOverride>

    @FetchRequest(fetchRequest: PersistenceController.recentIngestionsRequest(limit: 500))
    private var recentIngestions: FetchedResults<Ingestion>

    private var visibleScope: UnifiedSearchScope { isEyeOpen ? scope : .journal }
    private var categories: [String] { SubstanceRepo.shared.categories.map(\.name) }
    private var tags: [String] { PersonalSubstanceTags(overrides.flatMap { $0.personalTags.names }.sorted()).names }
    private var terms: [String] { SearchLogic.unifiedTerms(in: searchText) }
    private var journalIsFiltered: Bool {
        favoritesOnly || filters.journalType != .all || filters.ingestionKind != .any
    }
    private var filterIsActive: Bool {
        (visibleScope.includesJournal && journalIsFiltered)
            || (visibleScope.includesLibrary && filters.libraryIsFiltered)
    }

    var body: some View {
        scopedSearch
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .navigationTitle(startsInJournal ? "Search" : "Substances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { searchToolbar }
            .sheet(isPresented: $isShowingFilters) {
                UnifiedSearchFilterScreen(
                    scope: visibleScope, filters: $filters, favoritesOnly: $favoritesOnly,
                    categories: categories, tags: tags
                )
            }
            .sheet(isPresented: $isShowingAddCustomSubstance) {
                AddCustomSubstanceView(searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines)) { arguments in
                    if let destination = Navigator.substanceInfoDestination(for: arguments.substance.name) {
                        Navigator.shared.openInCurrentTab(destination)
                    }
                }
            }
            .sheet(item: $ingestionToEdit) { ingestion in
                EditIngestionScreen(ingestion: ingestion)
            }
            .sheet(item: $noteToEdit) { note in
                if let experience = note.experience {
                    EditTimedNoteScreen(timedNote: note, experience: experience)
                }
            }
            .task(id: searchText) {
                if !terms.isEmpty {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                }
                resultLimit = 50
                appliedText = searchText
            }
            .onChange(of: tags) { names in
                if let tag = filters.personalTag {
                    filters.personalTag = names.first {
                        PersonalSubstanceTags.key($0) == PersonalSubstanceTags.key(tag)
                    }
                }
            }
    }

    @ViewBuilder private var scopedSearch: some View {
        if isEyeOpen {
            if #available(iOS 16.4, *) {
                searchableResults.searchScopes($scope, activation: .onSearchPresentation) { scopeOptions }
            } else {
                searchableResults.searchScopes($scope) { scopeOptions }
            }
        } else {
            searchableResults
        }
    }

    private var scopeOptions: some View {
        ForEach(UnifiedSearchScope.allCases) { scope in
            Text(scope.title).tag(scope)
        }
    }

    @ViewBuilder private var searchableResults: some View {
        if #available(iOS 17, *) {
            localResults.searchable(
                text: $searchText, isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt
            )
        } else {
            localResults.searchable(
                text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt
            )
        }
    }

    @ToolbarContentBuilder private var searchToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            filterButton
            if visibleScope.includesLibrary || !terms.isEmpty { searchActions }
        }
    }

    private var filterButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            Label("Search Filters", systemImage: filterIsActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityAddTraits(filterIsActive ? .isSelected : [])
    }

    private var searchActions: some View {
        Menu {
            if !terms.isEmpty {
                Section {
                    if visibleScope.includesJournal { calendarLink }
                    if isEyeOpen { anodyneLink }
                }
            }
            if visibleScope.includesLibrary {
                Section {
                    createSubstanceButton
                    if customSubstances.count > 1 {
                        NavigationLink {
                            SimilarCustomSubstancesScreen()
                        } label: {
                            Label("Review Similar Names", systemImage: "rectangle.on.rectangle")
                        }
                    }
                }
            }
        } label: {
            Label("Search Actions", systemImage: "ellipsis.circle")
        }
    }

    private var calendarLink: some View {
        NavigationLink(value: GlobalNavigationDestination.calendar) {
            Label("Open Calendar", systemImage: "calendar")
        }
    }

    private var anodyneLink: some View {
        NavigationLink(value: GlobalNavigationDestination.anodyneSearch(
            query: searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        )) {
            Label(terms.isEmpty ? "Browse AnodyneWiki" : "Search AnodyneWiki", systemImage: "books.vertical")
        }
    }

    private var searchPrompt: Text {
        switch visibleScope {
        case .all: Text("Substances or journal entries")
        case .journal: Text("Journal entries or notes")
        case .library: Text("Substances")
        }
    }

    private var localResults: some View {
        List {
            if terms.isEmpty {
                Section {
                    if visibleScope.includesJournal { calendarLink }
                    if visibleScope.includesLibrary { anodyneLink }
                }
            }
            if filterIsActive {
                Section {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button("Clear Filters", action: clearVisibleFilters)
                }
            }
            if visibleScope.includesJournal {
                if terms.isEmpty && !journalIsFiltered {
                    if visibleScope == .journal {
                        Text("Search by substance, person, or note. Use quotes to match a phrase.")
                            .foregroundStyle(.secondary)
                    }
                } else if appliedText != searchText {
                    ProgressView().frame(maxWidth: .infinity)
                } else if filters.journalType == .notes {
                    UnifiedTimedNoteResults(
                        terms: terms, details: filters.noteDetails, favoritesOnly: favoritesOnly,
                        limit: resultLimit, edit: { noteToEdit = $0 }, showMore: { resultLimit += 50 }
                    )
                } else {
                    UnifiedJournalResults(
                        terms: terms, customSubstances: Array(customSubstances), type: filters.journalType,
                        ingestionKind: filters.ingestionKind,
                        favoritesOnly: favoritesOnly, limit: resultLimit, isEyeOpen: isEyeOpen,
                        edit: { ingestionToEdit = $0 },
                        showMore: { resultLimit += 50 }
                    )
                }
            }
            if visibleScope.includesLibrary {
                libraryResults
            }
            if isEyeOpen, !terms.isEmpty {
                Section { anodyneLink }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    private var eligibleCustomSubstances: [CustomSubstance] {
        guard filters.libraryType != .bundled else { return [] }
        return customSubstances.filter { custom in
            libraryFiltersMatch(custom.nameUnwrapped)
                && terms.allSatisfy { term in
                    SearchLogic.substanceName(custom.nameUnwrapped, matches: term)
                        || custom.explanationUnwrapped.localizedStandardContains(term)
                }
        }
    }

    private var eligibleBundledSubstances: [Substance] {
        guard filters.libraryType != .custom else { return [] }
        let candidates = SubstanceRepo.shared.substances.filter { substance in
            let names = [substance.name, substance.displayName] + substance.commonNames
            return libraryFiltersMatch(substance.name)
                && terms.allSatisfy { term in names.contains { SearchLogic.substanceName($0, matches: term) } }
        }
        let ranks = Dictionary(
            recentIngestions.map(\.substanceNameUnwrapped).uniqued().enumerated().map { ($1, $0) },
            uniquingKeysWith: min
        )
        let term = terms.first ?? ""
        return candidates.map { substance in
            let names = [substance.displayName, substance.name] + substance.commonNames
            let prefix = !term.isEmpty && names.contains { $0.cleanSearch.hasPrefix(term.cleanSearch) }
            let common = PersistenceController.shared.categories(for: substance.name).contains("common")
            return (substance, prefix, ranks[substance.name] ?? Int.max, common)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if lhs.3 != rhs.3 { return lhs.3 }
            return lhs.0.displayName.localizedStandardCompare(rhs.0.displayName) == .orderedAscending
        }.map(\.0)
    }

    private func libraryFiltersMatch(_ name: String) -> Bool {
        if !filters.categories.isEmpty {
            let categories = PersistenceController.shared.categories(for: name)
            guard filters.categories.allSatisfy(categories.contains) else { return false }
        }
        let personal = PersistenceController.shared.personalTags(for: name)
        if filters.untaggedOnly { return personal.names.isEmpty }
        if let tag = filters.personalTag { return personal.contains(tag) }
        return true
    }

    @ViewBuilder private var libraryResults: some View {
        let bundled = eligibleBundledSubstances
        let custom = eligibleCustomSubstances
        if visibleScope == .library, terms.isEmpty, isSiriTipVisible {
            SiriTipView(intent: SearchSubstancesIntent(), isVisible: $isSiriTipVisible)
        }
        if !bundled.isEmpty {
            Section("Substances") {
                ForEach(bundled) { substance in
                    SearchSubstanceRow(substance: substance)
                        .contextMenu { historyLink(substance.name) }
                }
            }
        }
        if !custom.isEmpty {
            Section("Custom Substances") {
                ForEach(custom) { substance in
                    NavigationLink(value: GlobalNavigationDestination.customSubstance(customSubstance: substance)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(substance.nameUnwrapped).font(.headline)
                            if !substance.explanationUnwrapped.isEmpty {
                                Text(substance.explanationUnwrapped).font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            WrappingHStack(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                                ForEach(PersistenceController.shared.categories(for: substance.nameUnwrapped), id: \.self) {
                                    Chip(name: $0)
                                }
                            }
                        }
                    }
                    .contextMenu { historyLink(substance.nameUnwrapped) }
                }
            }
        }
        if bundled.isEmpty && custom.isEmpty {
            Section("Library") {
                Text("No matching substances").foregroundStyle(.secondary)
                createSubstanceButton
            }
        }
    }

    private var createSubstanceButton: some View {
        Button {
            isShowingAddCustomSubstance = true
        } label: {
            Label("New Custom Substance", systemImage: "plus")
        }
    }

    private func historyLink(_ name: String) -> some View {
        Button {
            Navigator.shared.openInCurrentTab(.substanceHistory(name: name))
        } label: {
            Label("Open History", systemImage: "chart.bar")
        }
    }

    private var filterSummary: String {
        var labels: [String] = []
        if visibleScope.includesJournal {
            if favoritesOnly { labels.append(String(localized: "Favorites")) }
            if filters.journalType != .all { labels.append(filters.journalType.title) }
            if filters.journalType == .notes {
                if let mood = filters.noteDetails.mood {
                    labels.append(String(localized: "Mood \(mood.title)"))
                }
                if let energy = filters.noteDetails.energy {
                    labels.append(String(localized: "Energy \(energy.title)"))
                }
            } else if filters.ingestionKind != .any {
                labels.append(filters.ingestionKind.title)
            }
        }
        if visibleScope.includesLibrary {
            if filters.libraryType != .all { labels.append(filters.libraryType.title) }
            labels.append(contentsOf: filters.categories.sorted().map(\.localizedCapitalized))
            if filters.untaggedOnly { labels.append(String(localized: "Untagged")) }
            if let tag = filters.personalTag { labels.append(tag) }
        }
        return labels.formatted(.list(type: .and))
    }

    private func clearVisibleFilters() {
        if visibleScope.includesJournal {
            filters.clearJournal()
            favoritesOnly = false
        }
        if visibleScope.includesLibrary { filters.clearLibrary() }
    }
}

private struct UnifiedTimedNoteResults: View {
    let limit: Int
    let edit: (TimedNote) -> Void
    let showMore: () -> Void

    @FetchRequest private var notes: FetchedResults<TimedNote>

    init(
        terms: [String], details: TimedNoteDetails, favoritesOnly: Bool, limit: Int,
        edit: @escaping (TimedNote) -> Void, showMore: @escaping () -> Void
    ) {
        self.limit = limit
        self.edit = edit
        self.showMore = showMore
        let query = UnifiedJournalQuery(terms: terms, customSubstances: [], favoritesOnly: favoritesOnly)
        _notes = FetchRequest(fetchRequest: query.timedNotesRequest(limit: limit + 1, details: details))
    }

    var body: some View {
        Section("Timed Notes") {
            if notes.isEmpty {
                Text("No matching notes").foregroundStyle(.secondary)
            }
            ForEach(notes.prefix(limit)) { note in
                Button {
                    edit(note)
                } label: {
                    TimedNoteRow(timedNote: note) {
                        Text(note.timeUnwrapped.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .buttonStyle(.plain)
                .disabled(note.experience == nil)
            }
            if notes.count > limit {
                Button("Show More Timed Notes", action: showMore)
            }
        }
    }
}

private struct UnifiedJournalResults: View {
    let type: UnifiedSearchFilters.JournalType
    let limit: Int
    let isEyeOpen: Bool
    let edit: (Ingestion) -> Void
    let showMore: () -> Void

    @FetchRequest private var experiences: FetchedResults<Experience>
    @FetchRequest private var ingestions: FetchedResults<Ingestion>
    @AppStorage(PersistenceController.isHidingDosageDotsKey) private var hidesDosageDots = false

    init(
        terms: [String], customSubstances: [CustomSubstance], type: UnifiedSearchFilters.JournalType,
        ingestionKind: UnifiedJournalQuery.IngestionKind,
        favoritesOnly: Bool, limit: Int, isEyeOpen: Bool,
        edit: @escaping (Ingestion) -> Void, showMore: @escaping () -> Void
    ) {
        self.type = type
        self.limit = limit
        self.isEyeOpen = isEyeOpen
        self.edit = edit
        self.showMore = showMore
        let query = UnifiedJournalQuery(
            terms: terms, customSubstances: customSubstances, favoritesOnly: favoritesOnly,
            ingestionKind: ingestionKind
        )
        let experienceRequest = query.experiencesRequest(limit: limit + 1)
        if type == .ingestions { experienceRequest.predicate = NSPredicate(value: false) }
        let ingestionRequest = query.ingestionsRequest(limit: limit + 1)
        if type == .experiences { ingestionRequest.predicate = NSPredicate(value: false) }
        _experiences = FetchRequest(fetchRequest: experienceRequest)
        _ingestions = FetchRequest(fetchRequest: ingestionRequest)
    }

    var body: some View {
        if experiences.isEmpty && ingestions.isEmpty {
            Section("Journal") {
                Text("No matching entries").foregroundStyle(.secondary)
            }
        }
        if !experiences.isEmpty {
            Section("Experiences") {
                ForEach(experiences.prefix(limit)) { experience in
                    NavigationLink(value: GlobalNavigationDestination.experience(experience: experience)) {
                        ExperienceRowContent(
                            experience: experience, timeDisplayStyle: .regular, locationName: experience.location?.name
                        )
                    }
                }
            }
        }
        if !ingestions.isEmpty {
            Section("Ingestions") {
                ForEach(ingestions.prefix(limit)) { ingestion in
                    Button {
                        edit(ingestion)
                    } label: {
                        IngestionRow(ingestion: ingestion, isEyeOpen: isEyeOpen, isHidingDosageDots: hidesDosageDots) {
                            Text(ingestion.timeUnwrapped.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .contextMenu {
                        Button {
                            edit(ingestion)
                        } label: {
                            Label("Edit Ingestion", systemImage: "pencil")
                        }
                        if let start = ingestion.time {
                            Button {
                                Navigator.shared.showAddIngestionFullScreenCover(startingAt: start, endingAt: ingestion.endTime)
                            } label: {
                                Label("Add at Same Time", systemImage: "clock.badge.plus")
                            }
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        if let start = ingestion.time {
                            Button {
                                Navigator.shared.showAddIngestionFullScreenCover(startingAt: start, endingAt: ingestion.endTime)
                            } label: {
                                Label("Add at Same Time", systemImage: "clock.badge.plus")
                            }
                        }
                    }
                }
            }
        }
        if experiences.count > limit || ingestions.count > limit {
            Button("Show More Journal Results", action: showMore)
        }
    }
}
