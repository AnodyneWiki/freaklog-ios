import Foundation

struct CustomSubstanceModel: Identifiable {
    var id: String {
        name + units // id must be different from just name because else there is a bug when showing both the custom substance and original substance
    }

    let name: String
    let description: String
    let units: String
}

extension CustomSubstanceModel {
    init(_ customSubstance: CustomSubstance) {
        self.init(
            name: customSubstance.nameUnwrapped,
            description: customSubstance.explanationUnwrapped,
            units: customSubstance.unitsUnwrapped
        )
    }
}
