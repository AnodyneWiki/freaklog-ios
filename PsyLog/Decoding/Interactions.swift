import Foundation

struct Interactions: Decodable, Hashable {
    let uncertain: [String]
    let unsafe: [String]
    let dangerous: [String]
}
