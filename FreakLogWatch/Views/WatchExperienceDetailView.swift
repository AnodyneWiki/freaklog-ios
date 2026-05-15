import SwiftUI

struct WatchExperienceDetailView: View {
    @ObservedObject var experience: Experience

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(experience.sortDateUnwrapped, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WatchTimelinePreview(experience: experience)
                    .frame(height: 80)

                ForEach(experience.ingestionsSorted, id: \.objectID) { ing in
                    IngestionRowWatch(ingestion: ing)
                }

                if !experience.textUnwrapped.isEmpty {
                    Divider()
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(experience.textUnwrapped)
                        .font(.body)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(experience.titleUnwrapped)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IngestionRowWatch: View {
    @ObservedObject var ingestion: Ingestion

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ingestion.substanceColor.swiftUIColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(ingestion.substanceNameUnwrapped)
                    .font(.headline)
                    .lineLimit(1)
                Text(doseDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ingestion.timeUnwrapped, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var doseDescription: String {
        var parts: [String] = []
        if let dose = ingestion.doseUnwrapped {
            let unit = ingestion.units ?? ""
            parts.append("\(dose.formatted()) \(unit)".trimmingCharacters(in: .whitespaces))
        }
        parts.append(ingestion.administrationRouteUnwrapped.rawValue)
        return parts.joined(separator: " • ")
    }
}
