import Foundation

struct ConsumerWithIngestions: Identifiable, Comparable {
    let consumerName: String
    let ingestionsSorted: [Ingestion]
    let timelineModel: TimelineModel

    var id: String {
        consumerName
    }

    static func == (lhs: ConsumerWithIngestions, rhs: ConsumerWithIngestions) -> Bool {
        lhs.id == rhs.id
    }

    static func < (lhs: ConsumerWithIngestions, rhs: ConsumerWithIngestions) -> Bool {
        lhs.consumerName < rhs.consumerName
    }
}
