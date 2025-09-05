import Foundation

struct SubstanceWithToleranceAndColor: Identifiable, Hashable {
    var id: String {
        substanceName
    }

    let substanceName: String
    let full: String?
    let half: String?
    let zero: String?
    let crossTolerances: [String]
    let color: SubstanceColor
}

extension Substance {
    func toSubstanceWithToleranceAndColor(substanceColor: SubstanceColor) -> SubstanceWithToleranceAndColor {
        SubstanceWithToleranceAndColor(
            substanceName: name,
            full: tolerance?.full,
            half: tolerance?.half,
            zero: tolerance?.zero,
            crossTolerances: crossTolerances,
            color: substanceColor
        )
    }
}
