import Combine
import SwiftUI

struct ExperienceRow: View {
    @ObservedObject var experience: Experience
    let timeDisplayStyle: SaveableTimeDisplayStyle

    var body: some View {
        NavigationLink(value: GlobalNavigationDestination.experience(experience: experience)) {
            Group {
                if let location = experience.location {
                    ExperienceRowObservedLocation(experience: experience, location: location, timeDisplayStyle: timeDisplayStyle)
                } else {
                    ExperienceRowContent(experience: experience, timeDisplayStyle: timeDisplayStyle, locationName: nil)
                }
            }
            .swipeActions(allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task {
                        await IngestionDeletion.delete(experience: experience)
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                Button(role: .none) {
                    experience.isFavorite = !experience.isFavorite
                    PersistenceController.shared.saveViewContext()
                } label: {
                    Label("Toggle Favorite", systemImage: "star")
                }.tint(.yellow)
            }
        }
    }
}

// Observes the location too, so renaming it updates the row
struct ExperienceRowObservedLocation: View {
    @ObservedObject var experience: Experience
    @ObservedObject var location: ExperienceLocation
    let timeDisplayStyle: SaveableTimeDisplayStyle

    var body: some View {
        ExperienceRowContent(experience: experience, timeDisplayStyle: timeDisplayStyle, locationName: location.name)
    }
}

extension ExperienceRowContent {
    init(experience: Experience, timeDisplayStyle: SaveableTimeDisplayStyle, locationName: String?) {
        self.init(
            ingestionColors: experience.ingestionColors,
            title: experience.titleUnwrapped,
            distinctSubstanceNames: experience.distinctUsedSubstanceNames,
            sortDate: experience.sortDateUnwrapped,
            isFavorite: experience.isFavorite,
            timeDisplayStyle: timeDisplayStyle,
            locationName: locationName,
            rating: experience.overallRating?.optionUnwrapped ?? experience.maxRating,
            isCurrent: experience.isCurrent,
            consumerNames: experience.consumerNames
        )
    }
}

struct ExperienceRowContent: View {
    let ingestionColors: [Color]
    let title: String
    let distinctSubstanceNames: [String]
    let sortDate: Date
    let isFavorite: Bool
    let timeDisplayStyle: SaveableTimeDisplayStyle
    let locationName: String?
    let rating: ShulginRatingOption?
    let isCurrent: Bool
    let consumerNames: [String]

    var body: some View {
        TimelineView(.everyMinute) { _ in
            HStack {
                ExperienceColorRectangle(colors: ingestionColors)
                Spacer().frame(width: 10)
                VStack(alignment: .leading) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                    HStack {
                        Group {
                            if distinctSubstanceNames.isEmpty {
                                Text("No substance")
                            } else {
                                Text(distinctSubstanceNames, format: .list(type: .and))
                            }
                        }.font(.subheadline)
                        Spacer()
                        if let rating {
                            Text(rating.stringRepresentation)
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                    }
                    if !consumerNames.isEmpty {
                        Group {
                            Text("With ") + Text(consumerNames, format: .list(type: .and))
                        }
                        .foregroundColor(.secondary)
                        .font(.footnote)
                    }
                    HStack {
                        ExperienceTimeText(
                            time: sortDate,
                            timeDisplayStyle: timeDisplayStyle,
                            isCurrent: isCurrent
                        )
                        Spacer()
                        if let locationName {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin")
                                Text(locationName).lineLimit(1)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                    .font(.footnote)
                }
            }
        }
    }
}

#Preview {
    List {
        Section {
            ExperienceRowContent(
                ingestionColors: [.blue, .pink],
                title: "Your slightly longer title",
                distinctSubstanceNames: ["MDMA", "LSD"],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: true,
                timeDisplayStyle: .auto,
                locationName: "Longer location name",
                rating: .threePlus,
                isCurrent: true,
                consumerNames: ["Dave", "Carlo"]
            )
            ExperienceRowContent(
                ingestionColors: [.blue, .pink],
                title: "Your slightly longer title",
                distinctSubstanceNames: ["MDMA", "LSD"],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: true,
                timeDisplayStyle: .regular,
                locationName: nil,
                rating: .threePlus,
                isCurrent: false,
                consumerNames: []
            )
            ExperienceRowContent(
                ingestionColors: [.blue, .pink, .purple, .yellow],
                title: "Your title",
                distinctSubstanceNames: ["MDMA", "LSD", "Cocaine", "Amphetamine"],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: true,
                timeDisplayStyle: .relativeToNow,
                locationName: "Short location",
                rating: .threePlus,
                isCurrent: false,
                consumerNames: []
            )
            ExperienceRowContent(
                ingestionColors: [.blue, .pink],
                title: "Your title is not is a normal length",
                distinctSubstanceNames: ["MDMA", "LSD"],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: true,
                timeDisplayStyle: .relativeToNow,
                locationName: nil,
                rating: nil,
                isCurrent: false,
                consumerNames: []
            )
            ExperienceRowContent(
                ingestionColors: [.blue, .pink],
                title: "Your title short",
                distinctSubstanceNames: ["MDMA", "LSD"],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: true,
                timeDisplayStyle: .relativeToNow,
                locationName: "Home",
                rating: nil,
                isCurrent: false,
                consumerNames: []
            )
            ExperienceRowContent(
                ingestionColors: [],
                title: "Your title is not is a normal length",
                distinctSubstanceNames: [],
                sortDate: Date() - 5 * 60 * 60 - 30,
                isFavorite: false,
                timeDisplayStyle: .regular,
                locationName: nil,
                rating: .threePlus,
                isCurrent: false,
                consumerNames: []
            )
        }
    }.listStyle(.plain)
}
