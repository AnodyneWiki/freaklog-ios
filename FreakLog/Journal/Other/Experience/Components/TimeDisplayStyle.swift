import Foundation

enum TimeDisplayStyle {
    case regular, relativeToNow, relativeToStart, between
}


enum SaveableTimeDisplayStyle: String, CaseIterable, Identifiable {
    case regular, relativeToNow, relativeToStart, between, auto

    // `.auto` shows time relative to now while the experience is ongoing.
    func resolved(isCurrent: Bool) -> TimeDisplayStyle {
        switch self {
        case .regular: .regular
        case .relativeToNow: .relativeToNow
        case .relativeToStart: .relativeToStart
        case .between: .between
        case .auto: isCurrent ? .relativeToNow : .regular
        }
    }

    var id: Self {
        self
    }

    var text: String {
        switch self {
        case .regular:
            return "Regular time"
        case .relativeToNow:
            return "Time relative to now"
        case .relativeToStart:
            return "Time relative to start"
        case .between:
            return "Time between"
        case .auto:
            return "Auto"
        }
    }
}
