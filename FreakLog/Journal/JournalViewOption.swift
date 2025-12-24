import Foundation

enum JournalViewOption: Int, CaseIterable, Identifiable {
    case experiences = 0
    case allIngestions = 1

    var id: Int { rawValue }
    
    var text: String {
        switch self {
        case .experiences: return "Experiences"
        case .allIngestions: return "Ingestions"
        }
    }
}
