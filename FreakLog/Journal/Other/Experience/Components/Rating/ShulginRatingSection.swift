import SwiftUI

struct ShulginRatingSection: View {
    @ObservedObject var experience: Experience
    let hiddenRatings: [ObjectIdentifier]
    let showRating: (ObjectIdentifier) -> Void
    let hideRating: (ObjectIdentifier) -> Void
    let timeDisplayStyle: TimeDisplayStyle
    let firstIngestionTime: Date?

    enum SheetOption: Identifiable, Hashable {
        case editRegular(rating: ShulginRating)
        case editOverall(rating: ShulginRating)

        var id: Self {
            return self
        }
    }
    @State private var sheetToShow: SheetOption?

    var body: some View {
        Section("Shulgin Rating") {
            let ratingsSorted = experience.ratingsWithTimeSorted
            ForEach(Array(ratingsSorted.enumerated()), id: \.element) { index, rating in
                let previousRating = ratingsSorted[safe: index - 1]
                let isFirstRating = index == 0
                Button(action: {
                    sheetToShow = .editRegular(rating: rating)
                }, label: {
                    let isRatingHidden = hiddenRatings.contains(rating.id)
                    HStack(alignment: .center) {
                        if isRatingHidden {
                            Label("Hidden", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                        }
                        RatingRow(rating: rating) {
                            if timeDisplayStyle == .relativeToNow {
                                RelativeTimeText(date: rating.timeUnwrapped)
                            } else if let firstIngestionTime, timeDisplayStyle == .relativeToStart {
                                let dateComponents = DateDifference.between(firstIngestionTime, and: rating.timeUnwrapped)
                                Text(DateDifference.formattedWithMax2Units(dateComponents)) + Text(" after start")
                            } else if let firstIngestionTime, timeDisplayStyle == .between {
                                if isFirstRating {
                                    let dateComponents = DateDifference.between(firstIngestionTime, and: rating.timeUnwrapped)
                                    Text(DateDifference.formattedWithMax2Units(dateComponents)) + Text(" after first ingestion")
                                } else if let previousRating {
                                    let dateComponents = DateDifference.between(previousRating.timeUnwrapped, and: rating.timeUnwrapped)
                                    Text(DateDifference.formattedWithMax2Units(dateComponents)) + Text(" after last")
                                }
                            } else {
                                Text(rating.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                            }
                        }
                    }.foregroundColor(.primary)
                })
            }
            if let overallRating = experience.overallRating {
                Button(action: {
                    sheetToShow = .editOverall(rating: overallRating)
                }, label: {
                    RatingRow(rating: overallRating){
                        Text("Overall Rating")
                    }.foregroundColor(.primary)
                })
            }
        }.sheet(item: $sheetToShow) { sheetOption in
            NavigationStack {
                switch sheetOption {
                case .editRegular(let rating):
                    let isHidden = Binding(
                        get: { hiddenRatings.contains(rating.id) },
                        set: { newIsHidden in
                            if newIsHidden {
                                hideRating(rating.id)
                            } else {
                                showRating(rating.id)
                            }
                        }
                    )
                    EditRatingScreen(rating: rating, isHidden: isHidden)
                case .editOverall(let rating):
                    EditOverallRatingScreen(rating: rating)
                }
            }
        }
    }
}

struct RatingRow<Content: View>: View {
    @ObservedObject var rating: ShulginRating
    @ViewBuilder let timeText: Content

    var body: some View {
        HStack {
            timeText
            Spacer()
            Text(rating.optionUnwrapped.stringRepresentation)
        }.font(.headline)
    }
}
