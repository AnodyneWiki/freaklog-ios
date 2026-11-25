import AppIntents
import CoreData
import SwiftUI
import WrappingHStack

enum UnifiedSearchScope: String, CaseIterable, Identifiable {
    case all, journal, library, anodyne

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .journal: "Journal"
        case .library: "Library"
        case .anodyne: "AnodyneWiki"
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filters = UnifiedSearchFilters()
    @State private var isShowingFilters = false
    @State private var isShowingAddCustomSubstance = false
    @State private var ingestionToEdit: Ingestion?
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
    private var filterIsActive: Bool {
        (visibleScope.includesJournal && (favoritesOnly || filters.journalType != .all))
            || (visibleScope.includesLibrary && filters.libraryIsFiltered)
    }

    var body: some View {
        searchableResults
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

    private var scopedResults: some View {
        results.safeAreaInset(edge: .top, spacing: 0) {
            if isEyeOpen { scopeBar }
        }
    }

    private var scopePicker: some View {
        Picker("Search Scope", selection: $scope) {
            ForEach(UnifiedSearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
    }

    @ViewBuilder private var scopeBar: some View {
        VStack {
            if dynamicTypeSize.isAccessibilitySize {
                scopePicker.pickerStyle(.menu)
            } else {
                scopePicker.pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    @ViewBuilder private var searchableResults: some View {
        if #available(iOS 17, *) {
            scopedResults.searchable(
                text: $searchText, isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt
            )
        } else {
            scopedResults.searchable(
                text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt
            )
        }
    }

    @ToolbarContentBuilder private var searchToolbar: some ToolbarContent {
        if visibleScope != .anodyne {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                filterButton
                if visibleScope.includesLibrary { libraryActions }
            }
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

    private var libraryActions: some View {
        Menu {
            createSubstanceButton
            if customSubstances.count > 1 {
                NavigationLink {
                    SimilarCustomSubstancesScreen()
                } label: {
                    Label("Review Similar Names", systemImage: "rectangle.on.rectangle")
                }
            }
        } label: {
            Label("Library Actions", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder private var results: some View {
        if visibleScope == .anodyne {
            AnodyneSearchResults(searchText: searchText)
        } else {
            localResults
        }
    }

    private var searchPrompt: Text {
        switch visibleScope {
        case .all: Text("Substances or journal entries")
        case .journal: Text("Journal entries or notes")
        case .library: Text("Substances")
        case .anodyne: Text("AnodyneWiki")
        }
    }

    private var localResults: some View {
        List {
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
                if terms.isEmpty && !favoritesOnly {
                    if visibleScope == .journal {
                        Text("Search by substance, person, or note. Use quotes to match a phrase.")
                            .foregroundStyle(.secondary)
                    }
                } else if appliedText != searchText {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    UnifiedJournalResults(
                        terms: terms, customSubstances: Array(customSubstances), type: filters.journalType,
                        favoritesOnly: favoritesOnly, limit: resultLimit, isEyeOpen: isEyeOpen,
                        edit: { ingestionToEdit = $0 },
                        showMore: { resultLimit += 50 }
                    )
                }
            }
            if visibleScope.includesLibrary {
                libraryResults
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
            filters.journalType = .all
            favoritesOnly = false
        }
        if visibleScope.includesLibrary { filters.clearLibrary() }
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
        favoritesOnly: Bool, limit: Int, isEyeOpen: Bool,
        edit: @escaping (Ingestion) -> Void, showMore: @escaping () -> Void
    ) {
        self.type = type
        self.limit = limit
        self.isEyeOpen = isEyeOpen
        self.edit = edit
        self.showMore = showMore
        let query = UnifiedJournalQuery(terms: terms, customSubstances: customSubstances, favoritesOnly: favoritesOnly)
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
