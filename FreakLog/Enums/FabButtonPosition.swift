import Foundation
import SwiftUI

enum FabButtonPosition: String, Identifiable, CaseIterable {
    case left
    case center
    case right

    var id: FabButtonPosition {
        self
    }

    var alignment: Alignment {
        switch self {
        case .left:
            return .bottomLeading
        case .center:
            return .bottom
        case .right:
            return .bottomTrailing
        }
    }

    var text: String {
        switch self {
        case .left:
            return "Left"
        case .center:
            return "Center"
        case .right:
            return "Right"
        }
    }
}
