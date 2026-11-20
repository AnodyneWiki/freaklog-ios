import Foundation

extension Sequence where Element: Equatable {
    func uniqued() -> [Element] {
        var uniqueArray = [Element]()
        for element in self {
            if !uniqueArray.contains(element) {
                uniqueArray.append(element)
            }
        }
        return uniqueArray
    }
}

extension Sequence where Element: Hashable {
    // Order-preserving, O(n)
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
