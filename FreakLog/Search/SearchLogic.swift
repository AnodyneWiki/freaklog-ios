import Foundation

enum SearchLogic {
    static func getFilteredSubstancesSorted(substances: [Substance], searchText: String, namesToSortBy: [String]) -> [Substance] {
        let filteredSubstances = getFilteredSubstances(substances: substances, searchText: searchText)
        return filteredSubstances.sorted { sub1, sub2 in
            let indexOf1 = namesToSortBy.firstIndex(of: sub1.name)
            let indexOf2 = namesToSortBy.firstIndex(of: sub2.name)
            // true means sub1 first, false means sub2 first
            if let indexOf1 {
                if let indexOf2 {
                    return indexOf1 < indexOf2
                } else {
                    return true
                }
            } else {
                if indexOf2 != nil {
                    return false
                } else {
                    if sub1.categories.contains("common") {
                        return true
                    } else if sub2.categories.contains("common") {
                        return false
                    } else {
                        return true
                    }
                }
            }
        }
    }

    private static func getFilteredSubstances(substances: [Substance], searchText: String) -> [Substance] {
        let cleanedSearchText = searchText.cleanSearch
        let prefixResult = getSortedPrefixResults(substances: substances, lowerCaseSearchText: cleanedSearchText)
        if searchText.count < 3 {
            return prefixResult
        } else {
            if prefixResult.count < 3 {
                let containsResult = getSortedContainsResults(substances: substances, cleanSearch: cleanedSearchText)
                return containsResult.sorted { sub1, sub2 in
                    if prefixResult.contains(sub2) {
                        return true
                    } else if prefixResult.contains(sub1) {
                        return false
                    } else {
                        return true
                    }
                }
            } else {
                return prefixResult
            }
        }
    }

    private static func getSortedPrefixResults(substances: [Substance], lowerCaseSearchText: String) -> [Substance] {
        let mainPrefixMatches = substances.filter { sub in
            sub.name.lowercased().hasPrefix(lowerCaseSearchText)
        }
        if mainPrefixMatches.isEmpty {
            return substances.filter { sub in
                let names = sub.commonNames + [sub.name]
                return names.contains { name in
                    name.lowercased().hasPrefix(lowerCaseSearchText)
                }
            }
        } else {
            return mainPrefixMatches
        }
    }

    private static func getSortedContainsResults(substances: [Substance], cleanSearch: String) -> [Substance] {
        let mainPrefixMatches = substances.filter { sub in
            sub.name.cleanSearch.contains(cleanSearch)
        }
        if mainPrefixMatches.isEmpty {
            return substances.filter { sub in
                let names = sub.commonNames + [sub.name]
                return names.contains { name in
                    name.cleanSearch.contains(cleanSearch)
                }
            }
        } else {
            return mainPrefixMatches
        }
    }
}
