import SwiftUI

enum Tab: String, Codable, CaseIterable, Identifiable {
    case stats
    case journal
    case substances
    case safer
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .stats: return "Stats"
        case .journal: return "Journal"
        case .substances: return "Substances"
        case .safer: return "Safer"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .stats: return "chart.bar"
        case .journal: return "book"
        case .substances: return "pills"
        case .safer: return "cross.case"
        case .settings: return "gearshape"
        }
    }
    
    // Defines which tabs are mandatory and cannot be disabled
    var isMandatory: Bool {
        switch self {
        case .journal, .settings: return true
        default: return false
        }
    }
}
