import SwiftUI

struct ShulginRatingSection: View {
    @ObservedObject var experience: Experience
    @Binding var hiddenRatings: Set<ObjectIdentifier>
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
                Button(action: {
                    sheetToShow = .editRegular(rating: rating)
                }, label: {
                    let isRatingHidden = hiddenRatings.contains(rating.id)
                    HStack(alignment: .center) {
                        if isRatingHidden {
                            Label("Hidden", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                        }
                        RatingRow(rating: rating) {
                            EventTimeText(
                                time: rating.timeUnwrapped,
                                style: timeDisplayStyle,
                                firstIngestionTime: firstIngestionTime,
                                previousTime: previousRating?.timeUnwrapped
                            )
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
                    EditRatingScreen(rating: rating, isHidden: $hiddenRatings.contains(rating.id))
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
