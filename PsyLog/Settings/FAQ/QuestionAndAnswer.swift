import Foundation

struct QuestionAndAnswer: Identifiable, Hashable {
    let id = UUID()
    let question: String
    let answer: String

    static let list: [QuestionAndAnswer] = [
        QuestionAndAnswer(
            question: "Why was the app renamed to PsyLog?",
            answer: "This was done for several reasons - for one, to separate the app from the (implied) PW trademark, as well as to allow for data aggregation from other sources without causing confusion."
       ),
        QuestionAndAnswer(
            question: "Will this app always remain free?",
            answer: "Yes. We will never introduce any in-app purchases, subscriptions, or otherwise charge for features or the app as a whole."
       ),
        QuestionAndAnswer(
            question: "Why is an interaction or other info on a substance present in a data source but not in the app?",
            answer: "This is a bug - please report it by pressing 'Report an issue' in the settings tab."
        ),
        QuestionAndAnswer(
            question: "When does the app show an interaction warning?",
            answer: "If there is an interaction with a substance that was logged less than 2 days ago, or there is an interaction with any of the following: \(InteractionChecker.additionalInteractionsToCheck.joined(separator: ", "))."
        ),
        QuestionAndAnswer(
            question: "How can I change or add info on a substance (duration, dose, interactions and effects)?",
            answer: "By submitting corrections to the respective data source."
        ),
        QuestionAndAnswer(
            question: "How often are the data sources updated?",
            answer: "On every new version of the app. In the future, this may be replaced with an in-app data updater."
        ),
        QuestionAndAnswer(
            question: "How is the timeline drawn?",
            answer: "The onset duration range from the data source defines when the curve starts going up, the comeup how long it goes up for, the peak how long it stays up and the offset how long it takes to come down to baseline. The peak and offset durations are linearly interpolated based on the dose if possible, else it just chooses the middle value of the range. If some of the durations are missing, it draws a dotted line - e.g. if the onset and total time is given, it draws a line along the bottom for the onset, and then it draws a dotted curve to the end of the total time."
        ),
        QuestionAndAnswer(
            question: "Why does the timeline not stack the curves of redoses?",
            answer: "Since there is no way to determine exact effect or blood concentration from multiple ingestions, this is disabled by default. If you are aware of the possible inaccuracies, you can disable 'Draw redoses individually' in the settings tab."
        ),
    ]
}
