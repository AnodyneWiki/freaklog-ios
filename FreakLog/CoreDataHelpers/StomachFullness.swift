import Foundation

enum StomachFullness: String, CaseIterable, Identifiable, Codable {
    case empty, quarterFull, halfFull, full, veryFull

    var id: StomachFullness {
        self
    }

    var text: String {
        switch self {
        case .empty:
            return "Empty"
        case .quarterFull:
            return "Quarter Full"
        case .halfFull:
            return "Half Full"
        case .full:
            return "Full"
        case .veryFull:
            return "Very Full"
        }
    }

    var onsetDelayForOralInHours: Double {
        switch self {
        case .empty:
            return 0
        case .quarterFull:
            return 0.75
        case .halfFull:
            return 1.5
        case .full:
            return 3
        case .veryFull:
            return 4
        }
    }
}
