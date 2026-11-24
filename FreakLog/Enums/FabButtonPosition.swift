import Foundation
import SwiftUI

enum FabButtonPosition: String, Identifiable, CaseIterable {
    case left
    case right

    var id: FabButtonPosition {
        self
    }

    var alignment: Alignment {
        switch self {
        case .left:
            return .bottomLeading
        case .right:
            return .bottomTrailing
        }
    }

    var text: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}
