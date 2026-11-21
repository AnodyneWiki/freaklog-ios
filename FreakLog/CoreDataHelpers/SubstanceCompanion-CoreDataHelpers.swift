import Foundation

extension SubstanceCompanion {
    var color: SubstanceColor {
        colorAsText.flatMap(SubstanceColor.init(rawValue:)) ?? .fallback
    }

    var substanceNameUnwrapped: String {
        substanceName ?? "Unknown"
    }

    var ingestionsUnwrapped: [Ingestion] {
        ingestions?.allObjects as? [Ingestion] ?? []
    }
}
