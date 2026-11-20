import Foundation

struct SubstanceDataOverrideCodable: Codable {
  let substanceName: String
  let roas: [CustomRoaCodable]
}
