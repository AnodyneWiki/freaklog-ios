import Foundation

enum TimeDisplayStyle {
    case regular, relativeToNow, relativeToStart, between
}


enum SaveableTimeDisplayStyle: String, CaseIterable, Identifiable {
    case regular, relativeToNow, relativeToStart, between, auto

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
