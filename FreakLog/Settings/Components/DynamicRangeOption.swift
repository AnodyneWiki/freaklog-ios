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

    var id: Int { rawValue }
    
    var text: String {
        switch self {
        case .oneWeek: return "1 week"
        default: return "\(rawValue) hours"
        }
    }
}
