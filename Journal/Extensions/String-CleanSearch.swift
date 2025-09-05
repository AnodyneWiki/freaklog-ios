import Foundation

extension String {
    var cleanSearch: String {
        lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }
}
