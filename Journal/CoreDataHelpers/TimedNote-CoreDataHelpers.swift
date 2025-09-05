import CoreData

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

    var color: SubstanceColor {
        if let text = colorAsText, let color = SubstanceColor(rawValue: text) {
            return color
        } else {
            return SubstanceColor.red
        }
    }
}
