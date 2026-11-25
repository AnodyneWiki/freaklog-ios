import CoreData
import Foundation

enum SearchLogic {
    // Recently used substances first (in the order of `namesToSortBy`), then common ones, then the rest
    static func getFilteredSubstancesSorted(substances: [Substance], searchText: String, namesToSortBy: [String]) -> [Substance] {
        let rankByName = Dictionary(namesToSortBy.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return getFilteredSubstances(substances: substances, searchText: searchText).stablySorted { substance in
            let isCommon = PersistenceController.shared.categories(for: substance.name).contains("common")
            return [rankByName[substance.name] ?? Int.max, isCommon ? 0 : 1]
        }
    }

    // Prefix matches, or for longer searches with few prefix matches, all matches with the prefix ones first
    private static func getFilteredSubstances(substances: [Substance], searchText: String) -> [Substance] {
        let cleanedSearchText = searchText.cleanSearch
        let prefixResult = matches(in: substances) { $0.lowercased().hasPrefix(cleanedSearchText) }
        guard searchText.count >= 3, prefixResult.count < 3 else { return prefixResult }
        let prefixNames = Set(prefixResult.map(\.name))
        return matches(in: substances) { $0.cleanSearch.contains(cleanedSearchText) }
            .stablySorted { [prefixNames.contains($0.name) ? 0 : 1] }
    }

    // Substances whose name or the user's name for them matches, or if there are none, those with a matching common name
    private static func matches(in substances: [Substance], where isMatch: (String) -> Bool) -> [Substance] {
        let mainMatches = substances.filter { isMatch($0.name) || isMatch($0.displayName) }
        guard mainMatches.isEmpty else { return mainMatches }
        return substances.filter { substance in
            (substance.commonNames + [substance.name]).contains(where: isMatch)
        }
    }
}

private extension Array {
    // Sorts by the keys, compared in order, keeping the original order for equal keys
    func stablySorted(by keys: (Element) -> [Int]) -> [Element] {
        enumerated()
            .map { (keys: keys($0.element) + [$0.offset], element: $0.element) }
            .sorted { $0.keys.lexicographicallyPrecedes($1.keys) }
            .map(\.element)
    }
}

extension SearchLogic {
    static func unifiedTerms(in query: String) -> [String] {
        var terms: [String] = []
        var term = ""
        var isQuoted = false
        for character in query {
            if character == "\"" {
                if !term.isEmpty {
                    terms.append(term)
                    term = ""
                }
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !term.isEmpty { terms.append(term) }
                term = ""
            } else {
                term.append(character)
            }
        }
        if !term.isEmpty { terms.append(term) }
        return terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.uniqued()
    }

    static func matches(terms: [String], fields: [String]) -> Bool {
        terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
    }

    static func substanceName(_ name: String, matches term: String) -> Bool {
        let compact = term.cleanSearch
        return name.localizedStandardContains(term) || (!compact.isEmpty && name.cleanSearch.contains(compact))
    }
}

/// Each term can match a different field. For example, an experience can match two
/// substance names from separate ingestions plus a word in a timed note.
struct UnifiedJournalQuery {
    let terms: [String]
    let substanceNames: [String: [String]]
    let favoritesOnly: Bool

    init(terms: [String], customSubstances: [CustomSubstance], favoritesOnly: Bool) {
        self.terms = terms
        self.favoritesOnly = favoritesOnly
        let catalog = SubstanceRepo.shared.substances.map { substance in
            (substance.name, [substance.name, substance.displayName] + substance.commonNames)
        }
        substanceNames = Dictionary(uniqueKeysWithValues: terms.map { term in
            let bundled = catalog.filter { _, names in
                names.contains { SearchLogic.substanceName($0, matches: term) }
            }.map(\.0)
            let custom = customSubstances.filter { substance in
                SearchLogic.substanceName(substance.nameUnwrapped, matches: term)
                    || substance.explanationUnwrapped.localizedStandardContains(term)
            }.map(\.nameUnwrapped)
            return (term, (bundled + custom).uniqued())
        })
    }

    func experiencesRequest(limit: Int) -> NSFetchRequest<Experience> {
        let request = PersistenceController.experiencesRequest()
        request.fetchLimit = limit
        request.relationshipKeyPathsForPrefetching = ["ingestions", "ingestions.substanceCompanion", "ratings", "legacyLocation"]
        var clauses = terms.map { term in
            let fields = [
                "title", "text", "legacyLocation.name", "ANY timedNotes.note",
                "ANY ingestions.note", "ANY ingestions.substanceName", "ANY ingestions.consumerName",
                "ANY ingestions.customUnit.name", "ANY ingestions.formulation.name"
            ]
            var matches = fields.map { contains(term, field: $0) }
            appendSubstanceMatches(for: term, field: "ANY ingestions.substanceName", to: &matches)
            if let rating = ShulginRatingOption.allCases.first(where: {
                $0.stringRepresentation == term || $0.rawValue.localizedCaseInsensitiveCompare(term) == .orderedSame
            }) {
                matches.append(NSPredicate(format: "ANY ratings.option == %@", rating.rawValue))
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: matches) as NSPredicate
        }
        if favoritesOnly { clauses.append(NSPredicate(format: "isFavorite == YES")) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        return request
    }

    func ingestionsRequest(limit: Int) -> NSFetchRequest<Ingestion> {
        let request = PersistenceController.ingestionsRequest()
        request.fetchLimit = limit
        request.relationshipKeyPathsForPrefetching = ["customUnit", "experience", "formulation", "location", "substanceCompanion"]
        var clauses = terms.map { term in
            let fields = ["substanceName", "consumerName", "note", "customUnit.name",
                          "formulation.name", "experience.title", "location.name"]
            var matches = fields.map { contains(term, field: $0) }
            appendSubstanceMatches(for: term, field: "substanceName", to: &matches)
            return NSCompoundPredicate(orPredicateWithSubpredicates: matches) as NSPredicate
        }
        if favoritesOnly { clauses.append(NSPredicate(format: "experience.isFavorite == YES")) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        return request
    }

    private func appendSubstanceMatches(for term: String, field: String, to predicates: inout [NSPredicate]) {
        if let names = substanceNames[term], !names.isEmpty {
            predicates.append(NSPredicate(format: "\(field) IN %@", names))
        }
    }

    private func contains(_ term: String, field: String) -> NSPredicate {
        NSPredicate(format: "\(field) CONTAINS[cd] %@", term)
    }
}
