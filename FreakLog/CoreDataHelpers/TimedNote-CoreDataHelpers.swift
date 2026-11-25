import CoreData

enum TimedNoteMood: String, CaseIterable {
    case veryUnpleasant, unpleasant, neutral, pleasant, veryPleasant

    var title: String {
        switch self {
        case .veryUnpleasant: String(localized: "Very Unpleasant")
        case .unpleasant: String(localized: "Unpleasant")
        case .neutral: String(localized: "Neutral")
        case .pleasant: String(localized: "Pleasant")
        case .veryPleasant: String(localized: "Very Pleasant")
        }
    }
}

enum TimedNoteEnergy: String, CaseIterable {
    case veryLow, low, moderate, high, veryHigh

    var title: String {
        switch self {
        case .veryLow: String(localized: "Very Low")
        case .low: String(localized: "Low")
        case .moderate: String(localized: "Moderate")
        case .high: String(localized: "High")
        case .veryHigh: String(localized: "Very High")
        }
    }
}

struct TimedNoteDetails: Equatable {
    var mood: TimedNoteMood?
    var energy: TimedNoteEnergy?

    var isEmpty: Bool { mood == nil && energy == nil }
}

extension TimedNote: Comparable {
    public static func < (lhs: TimedNote, rhs: TimedNote) -> Bool {
        lhs.timeUnwrapped < rhs.timeUnwrapped
    }

    var creationDateUnwrapped: Date {
        creationDate ?? Date()
    }

    var timeUnwrapped: Date {
        time ?? Date()
    }

    var noteUnwrapped: String {
        note ?? ""
    }

    var details: TimedNoteDetails {
        get {
            TimedNoteDetails(
                mood: mood.flatMap(TimedNoteMood.init(rawValue:)),
                energy: energy.flatMap(TimedNoteEnergy.init(rawValue:))
            )
        }
        set {
            mood = newValue.mood?.rawValue
            energy = newValue.energy?.rawValue
        }
    }

    var webhookMessagesSorted: [WebhookMessage] {
        (webhookMessages as? Set<WebhookMessage> ?? []).sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
    }

    var color: SubstanceColor {
        if let text = colorAsText, let color = SubstanceColor(rawValue: text) {
            return color
        } else {
            return SubstanceColor.red
        }
    }
}
