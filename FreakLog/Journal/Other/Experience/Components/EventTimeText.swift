import SwiftUI

// The time of an ingestion, timed note or rating under a display style, optionally as a range.
// The first ingestion shows its clock time when relative to start or between; the first note or
// rating is measured from the first ingestion instead.
struct EventTimeText: View {
    let time: Date
    var endTime: Date?
    let style: TimeDisplayStyle
    let firstIngestionTime: Date?
    // The previous event of the same kind, nil for the first one
    let previousTime: Date?
    var isIngestion = false

    private enum Reference {
        case now
        case clock
        case since(Date, suffix: String)
    }

    private var reference: Reference {
        let isFirstIngestion = isIngestion && previousTime == nil
        switch style {
        case .relativeToNow:
            return .now
        case .relativeToStart:
            guard let firstIngestionTime, !isFirstIngestion else { return .clock }
            return .since(firstIngestionTime, suffix: " after start")
        case .between:
            if let previousTime {
                return .since(previousTime, suffix: " after last")
            } else if let firstIngestionTime, !isIngestion {
                return .since(firstIngestionTime, suffix: " after first ingestion")
            } else {
                return .clock
            }
        case .regular:
            return .clock
        }
    }

    var body: some View {
        let reference = reference
        if let endTime {
            HStack(spacing: 0) {
                label(for: time, reference: reference, isEnd: false)
                Text(" - ")
                label(for: endTime, reference: reference, isEnd: true)
            }
        } else {
            label(for: time, reference: reference, isEnd: true)
        }
    }

    @ViewBuilder
    private func label(for date: Date, reference: Reference, isEnd: Bool) -> some View {
        switch reference {
        case .now:
            RelativeTimeText(date: date)
        case .clock:
            // A range within one day only names the weekday once
            let isShortEnd = isEnd && style == .regular && endTime.map { Calendar.current.isDate(time, inSameDayAs: $0) } == true
            Text(date, format: isShortEnd ? .dateTime.hour().minute() : .dateTime.hour().minute().weekday(.abbreviated))
        case let .since(start, suffix):
            Text(DateDifference.maxTwoUnitsBetween(start, and: date)) + Text(isEnd ? suffix : "")
        }
    }
}
