import Foundation

enum AddIngestionDestination: Hashable {
    case interactions(substance: Substance)
    case saferUse(substance: Substance)
    case saferRoutes
}
