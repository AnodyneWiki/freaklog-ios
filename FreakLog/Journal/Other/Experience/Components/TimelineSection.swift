import SwiftUI

struct TimelineSection: View {
    let timelineModel: TimelineModel?
    let editIngestion: (Ingestion) -> Void
    let ingestionsSorted: [Ingestion]
    let timeDisplayStyle: TimeDisplayStyle
    let isEyeOpen: Bool
    let isHidingDosageDots: Bool
    let isCurrentExperience: Bool
    var timedNotes: [TimedNote] = []
    var firstIngestionTimeForNotes: Date?
    var editTimedNote: ((TimedNote) -> Void)?
    var remindAboutTimedNote: ((TimedNote) -> Void)?

    private enum Event: Identifiable {
        case ingestion(Ingestion)
        case note(TimedNote)

        var id: ObjectIdentifier {
            switch self {
            case .ingestion(let ingestion): ingestion.id
            case .note(let note): note.id
            }
        }

        var time: Date {
            switch self {
            case .ingestion(let ingestion): ingestion.timeUnwrapped
            case .note(let note): note.timeUnwrapped
            }
        }
    }

    private var events: [Event] {
        let ingestions = ingestionsSorted.map(Event.ingestion)
        let notes = editTimedNote == nil ? [] : timedNotes.map(Event.note)
        return (ingestions + notes).sorted { $0.time < $1.time }
    }

    var body: some View {
        Group {
            if let timelineModel, timelineModel.isWorthDrawing {
                EffectTimeline(
                    timelineModel: timelineModel,
                    height: 200,
                    timeDisplayStyle: timeDisplayStyle
                )
            }
            let events = events
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let previousTime = events[safe: index - 1]?.time
                switch event {
                case .ingestion(let ingestion):
                    ingestionRow(ingestion, previousTime: previousTime)
                case .note(let note):
                    if let editTimedNote {
                        Button {
                            editTimedNote(note)
                        } label: {
                            TimedNoteRow(timedNote: note) {
                                EventTimeText(
                                    time: note.timeUnwrapped,
                                    style: timeDisplayStyle,
                                    firstIngestionTime: firstIngestionTimeForNotes,
                                    previousTime: previousTime
                                )
                            }
                        }
                        .foregroundStyle(.primary)
                        .contextMenu {
                            if let remindAboutTimedNote {
                                Button {
                                    remindAboutTimedNote(note)
                                } label: {
                                    Label("Set Reminder", systemImage: "bell")
                                }
                            }
                        }
                    }
                }
            }
            if isCurrentExperience {
                let confirmed = ingestionsSorted.filter { !$0.isUnconfirmed }
                if timeDisplayStyle == .between, let time = confirmed.last(where: { $0.timeUnwrapped <= .now })?.time {
                    TimelineView(.everyMinute) { _ in
                        Text("Last ingestion was ") + Text(time, style: .relative) + Text(" ago")
                    }
                } else if timeDisplayStyle == .relativeToStart, let time = confirmed.first?.time {
                    TimelineView(.everyMinute) { context in
                        if time <= context.date {
                            Text("Now ") + Text(time, style: .relative) + Text(" after start")
                        } else {
                            Text("Starts in ") + Text(time, style: .relative)
                        }
                    }
                }
            }
        }
    }

    private func ingestionRow(_ ingestion: Ingestion, previousTime: Date?) -> some View {
        Button {
            editIngestion(ingestion)
        } label: {
            IngestionRow(
                ingestion: ingestion,
                isEyeOpen: isEyeOpen,
                isHidingDosageDots: isHidingDosageDots
            ) {
                EventTimeText(
                    time: ingestion.timeUnwrapped,
                    endTime: ingestion.endTime,
                    style: timeDisplayStyle,
                    firstIngestionTime: ingestionsSorted.first?.time,
                    previousTime: previousTime,
                    isIngestion: true
                )
            }
        }
        .modifier(SubstanceInfoSwipeAction(substanceName: ingestion.substanceNameUnwrapped))
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
