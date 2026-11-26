import Foundation

let openLatestExperience = "open-latest-experience"
// The app and its widget build together, while Debug and Release can coexist.
#if DEBUG
private let journalURLScheme = "woof.freaklog-debug"
#else
private let journalURLScheme = "woof.freaklog"
#endif
let continueJournalURL = URL(string: "\(journalURLScheme)://continue-journal")!
let dueTodayURL = URL(string: "\(journalURLScheme)://due-today")!

enum TimelineDisclaimers {
    static let heavyDose = "Heavy doses can have longer durations."
    static let capsule = "Hard (two-piece) capsules may need up to one hour to dissolve fully."
}

let namesOfLegalSubstances = [
    "Caffeine",
    "Myristicin",
    "Choline Bitartrate",
    "Citicoline",
    "Tyrosine",
]

let appName = "FreakLog"
let communityUrl = "https://discord.com/invite/DKfYmNrz6Z"
let repoUrl = "https://woof.rip/freaklog/freaklog-ios"

let minimumDistanceForDetectingDragGesture: CGFloat = 20
