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

enum ExperienceActivityLink {
    static func url(for experienceURI: URL?) -> URL {
        guard let experienceURI,
              var components = URLComponents(url: continueJournalURL, resolvingAgainstBaseURL: false)
        else { return continueJournalURL }
        components.queryItems = [URLQueryItem(name: "experience", value: experienceURI.absoluteString)]
        return components.url ?? continueJournalURL
    }

    static func experienceURI(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.queryItems, query.count == 1, query[0].name == "experience",
              let value = query[0].value, let uri = URL(string: value), uri.scheme == "x-coredata"
        else { return nil }
        components.query = nil
        guard components.url == continueJournalURL else { return nil }
        return uri
    }
}

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
