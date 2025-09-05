import SwiftUI

struct ExperiencesList: View {
    let isFavoriteFilterEnabled: Bool
    let isTimeRelative: Bool

    init(searchText: String, isFavoriteFilterEnabled: Bool, isTimeRelative: Bool) {
        self.isFavoriteFilterEnabled = isFavoriteFilterEnabled
        self.isTimeRelative = isTimeRelative
        let predicateFavorite = NSPredicate(
            format: "isFavorite == %@",
            NSNumber(value: true)
        )
        let predicateTitle = NSPredicate(
            format: "title CONTAINS[cd] %@",
            searchText as CVarArg
        )
        let predicateNotes = NSPredicate(
            format: "text CONTAINS[cd] %@",
            searchText as CVarArg
        )
        let predicateConsumer = NSPredicate(
            format: "%K.%K CONTAINS[cd] %@",
            #keyPath(Experience.ingestions),
            #keyPath(Ingestion.consumerName),
            searchText as CVarArg
        )
        let predicateSubstance = NSPredicate(
            format: "%K.%K CONTAINS[cd] %@",
            #keyPath(Experience.ingestions),
            #keyPath(Ingestion.substanceName),
            searchText as CVarArg
        )
        var experiencePredicate: NSPredicate?
        let orPredicates = NSCompoundPredicate(orPredicateWithSubpredicates: [predicateTitle, predicateSubstance, predicateNotes, predicateConsumer])
        if isFavoriteFilterEnabled {
            if searchText.isEmpty {
                experiencePredicate = predicateFavorite
            } else {
                experiencePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicateFavorite, orPredicates])
            }
        } else {
            if searchText.isEmpty {
                experiencePredicate = nil
            } else {
                experiencePredicate = orPredicates
            }
        }
        _fetchedExperiences = FetchRequest<Experience>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)],
            predicate: experiencePredicate)
    }

    @FetchRequest var fetchedExperiences: FetchedResults<Experience>

    @Environment(\.isSearching) private var isSearching

    var body: some View {
        ZStack {
            List(fetchedExperiences) { experience in
                ExperienceRow(experience: experience, isTimeRelative: isTimeRelative)
            }
            .listStyle(.plain)
            if fetchedExperiences.isEmpty {
                if isSearching {
                    Text("No experiences match the search")
                        .foregroundColor(.secondary)
                } else if isFavoriteFilterEnabled {
                    Text("No favorites match the search")
                        .foregroundColor(.secondary)
                } else {
                    Text("No ingestions yet")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
