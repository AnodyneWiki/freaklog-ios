import Foundation

extension SubstanceCompanion {
    var color: SubstanceColor {
        if let text = colorAsText, let color = SubstanceColor(rawValue: text) {
            return color
        } else {
            return SubstanceColor.red
        }
    }

    var substanceNameUnwrapped: String {
        substanceName ?? "Unknown"
    }

    var ingestionsUnwrapped: [Ingestion] {
        ingestions?.allObjects as? [Ingestion] ?? []
    }

    static var fakeMDMA: SubstanceCompanion {
        let companion = SubstanceCompanion(context: PersistenceController.preview.viewContext)
        companion.substanceName = "MDMA"
        companion.colorAsText = SubstanceColor.pink.rawValue
        return companion
    }

    static var fakeLSD: SubstanceCompanion {
        let companion = SubstanceCompanion(context: PersistenceController.preview.viewContext)
        companion.substanceName = "LSD"
        companion.colorAsText = SubstanceColor.blue.rawValue
        return companion
    }
}
