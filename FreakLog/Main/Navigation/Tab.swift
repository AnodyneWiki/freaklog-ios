import SwiftUI

enum Tab: String, Codable, CaseIterable, Identifiable {
    case stats
    case journal
    case substances
    case tools
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .stats: return "Stats"
        case .journal: return "Journal"
        case .substances: return "Substances"
        case .tools: return "Tools"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .stats: return "chart.bar"
        case .journal: return "book"
        case .substances: return "pills"
        case .tools: return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape"
        }
    }

    var requiresOpenEye: Bool {
        switch self {
        case .substances, .tools: return true
        default: return false
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
