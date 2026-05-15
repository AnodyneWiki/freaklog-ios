import SwiftUI
import CoreData

struct NowView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)],
        animation: .default
    )
    private var experiences: FetchedResults<Experience>

    var activeExperiences: [Experience] {
        let now = Date()
        return experiences.filter { exp in
            guard let firstTime = exp.ingestionsSorted.first?.timeUnwrapped else { return false }
            // active if any ingestion is within last 24h
            return firstTime > now.addingTimeInterval(-60 * 60 * 24)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeExperiences.isEmpty {
                    ContentUnavailableView(
                        "Nothing Active",
                        systemImage: "moon.zzz",
                        description: Text("Recent ingestions will appear here.")
                    )
                } else {
                    List {
                        ForEach(activeExperiences) { experience in
                            NavigationLink {
                                WatchExperienceDetailView(experience: experience)
                            } label: {
                                NowExperienceRow(experience: experience)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Now")
        }
    }
}

struct NowExperienceRow: View {
    @ObservedObject var experience: Experience

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(experience.titleUnwrapped)
                .font(.headline)
                .lineLimit(1)
            ForEach(experience.myIngestionsSorted.prefix(3), id: \.objectID) { ing in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ing.substanceColor.swiftUIColor)
                        .frame(width: 8, height: 8)
                    Text(ing.substanceNameUnwrapped)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(ing.timeUnwrapped, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            WatchTimelinePreview(experience: experience)
                .frame(height: 40)
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
