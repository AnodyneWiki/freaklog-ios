import Foundation

struct IngestionSection: Identifiable {
    let id: String // Start of day date string
    let date: Date
    var ingestions: [Ingestion]
}
