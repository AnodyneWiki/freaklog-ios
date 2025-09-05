import SwiftUI

struct TimedNoteRow<Content: View>: View {
    @ObservedObject var timedNote: TimedNote
    @ViewBuilder var timeText: Content

    var body: some View {
        TimedNoteRowContent(
            note: timedNote.noteUnwrapped,
            color: timedNote.color,
            isPartOfTimeline: timedNote.isPartOfTimeline
        ) {
            timeText
        }
    }
}

private struct TimedNoteRowContent<Content: View>: View {
    let note: String
    let color: SubstanceColor
    let isPartOfTimeline: Bool
    @ViewBuilder var timeText: Content

    var body: some View {
        HStack {
            Group {
                if isPartOfTimeline {
                    TimedNoteDottedLine(color: color.swiftUIColor)
                } else {
                    Spacer().frame(width: StrokeStyle.timedNoteLineWidth)
                }
            }
            .padding(.vertical, 8)
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    timeText.font(.headline)
                    if !isPartOfTimeline {
                        Text(" (not part of timeline)").font(.footnote).foregroundColor(.secondary)
                    }
                }

                Text(note).font(.subheadline)
            }
        }
    }
}

#Preview {
    List {
        TimedNoteRowContent(
            note: "Your note",
            color: .blue,
            isPartOfTimeline: true
        ) {
            Text("Sat 7:37")
        }
        TimedNoteRowContent(
            note: "Your note",
            color: .blue,
            isPartOfTimeline: false
        ) {
            Text("Sat 7:37")
        }
    }
}
