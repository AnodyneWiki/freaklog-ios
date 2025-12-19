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

