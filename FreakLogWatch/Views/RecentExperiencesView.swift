import SwiftUI
import CoreData

struct RecentExperiencesView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)],
        animation: .default
    )
    private var experiences: FetchedResults<Experience>

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(experiences.prefix(50))) { experience in
                    NavigationLink {
                        WatchExperienceDetailView(experience: experience)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(experience.titleUnwrapped)
                                .font(.headline)
                                .lineLimit(1)
                            Text(experience.sortDateUnwrapped, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                ForEach(uniqueColors(for: experience), id: \.self) { color in
                                    Circle()
                                        .fill(color.swiftUIColor)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Recent")
            .overlay {
                if experiences.isEmpty {
                    ContentUnavailableView(
                        "No Experiences",
                        systemImage: "tray",
                        description: Text("Add ingestions on iPhone or Watch.")
                    )
                }
            }
        }
    }

    private func uniqueColors(for experience: Experience) -> [SubstanceColor] {
        var seen: Set<SubstanceColor> = []
        var ordered: [SubstanceColor] = []
        for ing in experience.myIngestionsSorted {
            let c = ing.substanceColor
            if !seen.contains(c) {
                seen.insert(c)
                ordered.append(c)
            }
        }
        return Array(ordered.prefix(6))
    }
}
