import Foundation

enum SearchLogic {
    // Recently used substances first (in the order of `namesToSortBy`), then common ones, then the rest
    static func getFilteredSubstancesSorted(substances: [Substance], searchText: String, namesToSortBy: [String]) -> [Substance] {
        let rankByName = Dictionary(namesToSortBy.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return getFilteredSubstances(substances: substances, searchText: searchText).stablySorted { substance in
            [rankByName[substance.name] ?? Int.max, substance.categories.contains("common") ? 0 : 1]
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

    // Substances whose name matches, or if there are none, those with a matching common name
    private static func matches(in substances: [Substance], where isMatch: (String) -> Bool) -> [Substance] {
        let mainMatches = substances.filter { isMatch($0.name) }
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
