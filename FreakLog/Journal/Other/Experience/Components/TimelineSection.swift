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
        case ingestion(Ingestion, previousTime: Date?)
        case note(TimedNote, previousTime: Date?)

        var id: ObjectIdentifier {
            switch self {
            case .ingestion(let ingestion, _): ingestion.id
            case .note(let note, _): note.id
            }
        }

        var time: Date {
            switch self {
            case .ingestion(let ingestion, _): ingestion.timeUnwrapped
            case .note(let note, _): note.timeUnwrapped
            }
        }
    }

    private var events: [Event] {
        let ingestions = ingestionsSorted.enumerated().map {
            Event.ingestion($0.element, previousTime: ingestionsSorted[safe: $0.offset - 1]?.timeUnwrapped)
        }
        let notes = timedNotes.enumerated().map {
            Event.note($0.element, previousTime: timedNotes[safe: $0.offset - 1]?.timeUnwrapped)
        }
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
            ForEach(events) { event in
                switch event {
                case let .ingestion(ingestion, previousTime):
                    ingestionRow(ingestion, previousTime: previousTime)
                case let .note(note, previousTime):
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
