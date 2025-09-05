import Foundation

extension String {
    func caseInsensitiveContains(_ text: String) -> Bool {
        return range(of: text, options: .caseInsensitive) != nil
    }
}
