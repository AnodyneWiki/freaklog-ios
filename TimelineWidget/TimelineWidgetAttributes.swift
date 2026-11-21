import ActivityKit

struct TimelineWidgetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        static func == (lhs: TimelineWidgetAttributes.ContentState, rhs: TimelineWidgetAttributes.ContentState) -> Bool {
            lhs.substanceGroups == rhs.substanceGroups
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(substanceGroups)
        }

        // Dynamic stateful properties about your activity go here!
        var substanceGroups: [SubstanceIngestionGroup]
        var everythingForEachRating: [EverythingForOneRating]
        var everythingForEachTimedNote: [EverythingForOneTimedNote]
        var areRedosesDrawnIndividually: Bool
        var areSubstanceHeightsIndependent: Bool
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

extension TimelineWidgetAttributes.ContentState {
    var timelineModel: TimelineModel {
        TimelineModel(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
        )
    }
}
