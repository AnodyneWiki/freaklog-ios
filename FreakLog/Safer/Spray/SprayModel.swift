import Foundation

struct SprayModel: Identifiable, Equatable {
    var id: String {
        name + numSprays.description + contentInMl.description
    }

    let name: String
    let numSprays: Double
    let contentInMl: Double
    let spray: Spray?
}
