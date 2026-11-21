import Foundation

enum DynamicRangeOption: Int, CaseIterable, Identifiable {
    case sixHours = 6
    case twelveHours = 12
    case eighteenHours = 18
    case twentyFourHours = 24
    case thirtySixHours = 36
    case fortyEightHours = 48
    case seventyTwoHours = 72
    case oneWeek = 168

    // The range chosen in journal settings, read outside of views
    static var current: DynamicRangeOption {
        DynamicRangeOption(rawValue: UserDefaults.standard.integer(forKey: PersistenceController.dynamicExperienceRangeHoursKey))
            ?? .twentyFourHours
    }

    var id: Int { rawValue }

    var duration: TimeInterval {
        TimeInterval(rawValue) * 60 * 60
    }

    // Whether the date lies within this range before now
    func containsRecent(_ date: Date) -> Bool {
        date > Date.now.addingTimeInterval(-duration)
    }
    
    var text: String {
        switch self {
        case .oneWeek: return "1 week"
        default: return "\(rawValue) hours"
        }
    }
}
