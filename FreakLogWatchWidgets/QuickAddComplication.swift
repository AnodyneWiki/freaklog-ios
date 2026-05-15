import WidgetKit
import SwiftUI

struct QuickAddEntry: TimelineEntry { let date: Date }

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) { completion(QuickAddEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: Date())], policy: .never))
    }
}

struct QuickAddComplication: Widget {
    let kind = "QuickAddComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { _ in
            QuickAddEntryView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to log an ingestion.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct QuickAddEntryView: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("FreakLog: Add")
        case .accessoryCircular:
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        case .accessoryCorner:
            Image(systemName: "plus.circle.fill")
                .widgetLabel { Text("Add Ingestion") }
        case .accessoryRectangular:
            HStack {
                Image(systemName: "plus.circle.fill").font(.title3)
                VStack(alignment: .leading) {
                    Text("Quick Add").font(.headline)
                    Text("Log a substance").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            Image(systemName: "plus.circle")
        }
    }
}
