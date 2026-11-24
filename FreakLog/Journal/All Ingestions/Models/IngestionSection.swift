import CoreData
import Foundation

struct IngestionSection: Identifiable {
    // Ingestions and timed notes of a day are listed together, the newest first
    enum Item: Identifiable {
        case ingestion(Ingestion)
        case timedNote(TimedNote)

        var id: NSManagedObjectID {
            switch self {
            case .ingestion(let ingestion): ingestion.objectID
            case .timedNote(let timedNote): timedNote.objectID
            }
        }

        // Notes have no substance
        var substanceName: String? {
            if case .ingestion(let ingestion) = self { ingestion.substanceNameUnwrapped } else { nil }
        }

        var time: Date {
            switch self {
            case .ingestion(let ingestion): ingestion.timeUnwrapped
            case .timedNote(let timedNote): timedNote.timeUnwrapped
            }
        }
    }

    let id: String // Start of day date string
    let date: Date
    var items: [Item]
}
