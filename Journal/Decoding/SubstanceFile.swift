import Foundation

struct SubstanceFile: Decodable {
    let categories: [Category]
    let substances: [Substance]
}
