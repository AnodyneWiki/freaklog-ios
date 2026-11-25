import SwiftUI
import WidgetKit

@main
struct TimelineWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimelineWidgetLiveActivity()
        JournalLauncherWidget<ContinueJournal>()
        JournalLauncherWidget<DueToday>()
    }
}

private protocol JournalLauncher {
    static var kind: String { get }
    static var title: LocalizedStringKey { get }
    static var description: LocalizedStringKey { get }
    static var symbol: String { get }
    static var destination: URL { get }
}

private enum ContinueJournal: JournalLauncher {
    static let kind = "ContinueJournal"
    static let title: LocalizedStringKey = "Continue Journal"
    static let description: LocalizedStringKey = "Open your latest active experience."
    static let symbol = "book.closed"
    static let destination = continueJournalURL
}

private enum DueToday: JournalLauncher {
    static let kind = "DueToday"
    static let title: LocalizedStringKey = "Due Today"
    static let description: LocalizedStringKey = "Open your routines for today."
    static let symbol = "calendar.badge.clock"
    static let destination = dueTodayURL
}

private struct JournalLauncherWidget<Launcher: JournalLauncher>: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Launcher.kind, provider: LauncherProvider()) { _ in
            Group {
                if #available(iOSApplicationExtension 17, *) {
                    launcher.containerBackground(.fill.tertiary, for: .widget)
                } else {
                    launcher
                }
            }
            .widgetURL(Launcher.destination)
        }
        .configurationDisplayName(Text(Launcher.title))
        .description(Text(Launcher.description))
        .supportedFamilies([.systemSmall])
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: Launcher.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            Text(Launcher.title)
                .font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct LauncherProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
