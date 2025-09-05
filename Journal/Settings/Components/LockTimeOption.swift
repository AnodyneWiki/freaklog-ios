import Foundation

enum LockTimeOption: String, Identifiable, CaseIterable {
    case immediately
    case after5Minutes
    case after10Minutes
    case after30Minutes
    case after1Hour

    var id: LockTimeOption {
        self
    }

    var timeInterval: TimeInterval {
        switch self {
        case .immediately:
            return 0
        case .after5Minutes:
            return 5 * 60
        case .after10Minutes:
            return 10 * 60
        case .after30Minutes:
            return 30 * 60
        case .after1Hour:
            return 60 * 60
        }
    }

    var text: String {
        switch self {
        case .immediately:
            return "Immediately"
        case .after5Minutes:
            return "After 5 minutes"
        case .after10Minutes:
            return "After 10 minutes"
        case .after30Minutes:
            return "After 30 minutes"
        case .after1Hour:
            return "After 1 hour"
        }
    }
}
