import SwiftUI
import WidgetKit

struct NextRoutineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextRoutine", provider: NextRoutineProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                NextRoutineWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                NextRoutineWidgetView(entry: entry)
                    .padding(12)
            }
        }
        .configurationDisplayName("Next Routine")
        .description("See when your next routine is scheduled.")
        .supportedFamilies([.systemSmall])
    }
}

private struct NextRoutineEntry: TimelineEntry {
    let date: Date
    let routine: RoutineQuickSnapshot.Preview?
    var phoneLocked = false
}

private struct NextRoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextRoutineEntry {
        let today = Calendar.current.dateInterval(of: .day, for: .now)
        return NextRoutineEntry(date: .now, routine: today.map {
            RoutineQuickSnapshot.Preview(scheduledAt: .now.addingTimeInterval(900), dayStart: $0.start,
                                         dayEnd: $0.end, action: nil)
        })
    }

    func getSnapshot(in context: Context, completion: @escaping (NextRoutineEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entry(at: .now, in: RoutineQuickSnapshot.read()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextRoutineEntry>) -> Void) {
        let snapshot = RoutineQuickSnapshot.read()
        let now = Date.now
        let boundaries = snapshot.previews.flatMap { [$0.dayStart, $0.dayEnd] }.filter { $0 > now }
        let dates = [now] + Set(boundaries).sorted()
        completion(Timeline(entries: dates.map { entry(at: $0, in: snapshot) }, policy: .never))
    }

    private func entry(at date: Date, in snapshot: RoutineQuickSnapshot) -> NextRoutineEntry {
        NextRoutineEntry(date: date, routine: snapshot.next(at: date), phoneLocked: snapshot.phoneLocked)
    }
}

private struct NextRoutineWidgetView: View {
    let entry: NextRoutineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Next Routine", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer(minLength: 2)
            if let routine = entry.routine {
                Group {
                    if entry.date >= routine.dayStart {
                        Text(routine.scheduledAt, format: .dateTime.hour().minute())
                    } else {
                        Text(routine.scheduledAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    }
                }
                .font(.title3.bold())
                .privacySensitive()
                if #available(iOSApplicationExtension 17.0, *), entry.date >= routine.dayStart,
                   let action = routine.action {
                    Button(intent: MarkRoutineTakenIntent(action: action)) {
                        Text("Mark Taken")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text(entry.phoneLocked ? "Open FreakLog" : "No Upcoming Routines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(dueTodayURL)
    }
}
