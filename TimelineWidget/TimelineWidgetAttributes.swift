import ActivityKit
import Foundation

struct TimelineWidgetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var substanceGroups: [SubstanceIngestionGroup]
        var everythingForEachRating: [EverythingForOneRating]
        var everythingForEachTimedNote: [EverythingForOneTimedNote]
        var areRedosesDrawnIndividually: Bool
        var areSubstanceHeightsIndependent: Bool
        var combinesComparableRoutes: Bool? = nil
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
    // The shown experience's object ID URI, so the app can keep the activity up to date after a relaunch
    var experienceURI: URL?
}

extension TimelineWidgetAttributes.ContentState {
    var timelineModel: TimelineModel {
        TimelineModel(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote,
            areRedosesDrawnIndividually: areRedosesDrawnIndividually,
            areSubstanceHeightsIndependent: areSubstanceHeightsIndependent,
            combinesComparableRoutes: combinesComparableRoutes ?? false
        )
    }
}
