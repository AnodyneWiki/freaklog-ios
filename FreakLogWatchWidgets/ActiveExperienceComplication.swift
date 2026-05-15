import WidgetKit
import SwiftUI
import CoreData

struct ActiveExperienceEntry: TimelineEntry {
    let date: Date
    let activeIngestion: ActiveIngestionSnapshot?
}

struct ActiveIngestionSnapshot {
    let substanceName: String
    let dose: Double?
    let units: String?
    let time: Date
    let colorRaw: String?

    var color: SubstanceColor {
        SubstanceColor(rawValue: colorRaw ?? "") ?? .purple
    }
}

struct ActiveExperienceProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveExperienceEntry {
        ActiveExperienceEntry(
            date: Date(),
            activeIngestion: ActiveIngestionSnapshot(
                substanceName: "Caffeine", dose: 100, units: "mg",
                time: Date().addingTimeInterval(-1800), colorRaw: "brown"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveExperienceEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveExperienceEntry>) -> Void) {
        let entry = loadEntry()
        let next = Date().addingTimeInterval(60 * 15)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> ActiveExperienceEntry {
        let ctx = PersistenceController.shared.viewContext
        let req: NSFetchRequest<Ingestion> = Ingestion.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)]
        req.fetchLimit = 1
        let cutoff = Date().addingTimeInterval(-60 * 60 * 24)
        req.predicate = NSPredicate(format: "time >= %@", cutoff as NSDate)
        let snap: ActiveIngestionSnapshot? = (try? ctx.fetch(req).first).flatMap { ing in
            ActiveIngestionSnapshot(
                substanceName: ing.substanceNameUnwrapped,
                dose: ing.doseUnwrapped,
                units: ing.units,
                time: ing.timeUnwrapped,
                colorRaw: ing.color
            )
        }
        return ActiveExperienceEntry(date: Date(), activeIngestion: snap)
    }
}

struct ActiveExperienceComplication: Widget {
    let kind = "ActiveExperienceComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveExperienceProvider()) { entry in
            ActiveExperienceEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Now")
        .description("Shows your most recent ingestion.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct ActiveExperienceEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ActiveExperienceEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    @ViewBuilder var inline: some View {
        if let ing = entry.activeIngestion {
            Text("\(ing.substanceName) • \(ing.time, style: .relative)")
        } else {
            Text("FreakLog: idle")
        }
    }

    @ViewBuilder var circular: some View {
        if let ing = entry.activeIngestion {
            ZStack {
                Circle().fill(ing.color.swiftUIColor.opacity(0.6))
                Text(initials(ing.substanceName))
                    .font(.caption2.bold())
            }
        } else {
            Image(systemName: "moon.zzz")
        }
    }

    @ViewBuilder var corner: some View {
        if let ing = entry.activeIngestion {
            Image(systemName: "drop.fill")
                .foregroundStyle(ing.color.swiftUIColor)
                .widgetLabel {
                    Text("\(ing.substanceName) \(ing.time, style: .relative)")
                }
        } else {
            Image(systemName: "moon.zzz")
        }
    }

    @ViewBuilder var rectangular: some View {
        if let ing = entry.activeIngestion {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(ing.color.swiftUIColor).frame(width: 8, height: 8)
                    Text(ing.substanceName).font(.headline).lineLimit(1)
                }
                if let dose = ing.dose, let units = ing.units {
                    Text("\(dose.formatted()) \(units)").font(.caption2)
                }
                Text(ing.time, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading) {
                Text("FreakLog").font(.headline)
                Text("Nothing active").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func initials(_ s: String) -> String {
        let parts = s.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)) }
        return String(s.prefix(2))
    }
}
