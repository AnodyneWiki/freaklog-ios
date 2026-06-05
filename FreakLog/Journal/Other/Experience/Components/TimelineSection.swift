import SwiftUI

struct TimelineSection: View {
    let timelineModel: TimelineModel
    let editIngestion: (Ingestion) -> Void
    let ingestionsSorted: [Ingestion]
    let timeDisplayStyle: TimeDisplayStyle
    let isEyeOpen: Bool
    let isHidingDosageDots: Bool
    let hiddenIngestions: [ObjectIdentifier]
    let isCurrentExperience: Bool

    var body: some View {
        Group {
            if timelineModel.isWorthDrawing {
                EffectTimeline(
                    timelineModel: timelineModel,
                    height: 200,
                    timeDisplayStyle: timeDisplayStyle
                )
            }
            let firstIngestionTime = ingestionsSorted.first?.time
            ForEach(Array(ingestionsSorted.enumerated()), id: \.element) { index, ingestion in
                let previousIngestion = ingestionsSorted[safe: index - 1]
                let isFirstIngestion = index == 0
                let isLastIngestion = index == ingestionsSorted.count - 1

                Button {
                    editIngestion(ingestion)
                } label: {
                    HStack(alignment: .center) {
                        IngestionRow(
                            ingestion: ingestion,
                            isEyeOpen: isEyeOpen,
                            isHidingDosageDots: isHidingDosageDots,
                            timeText: {
                                if let endTime = ingestion.endTime {
                                    if timeDisplayStyle == .relativeToNow {
                                        TimeRangeRepresentation {
                                            RelativeTimeText(date: ingestion.timeUnwrapped)
                                        } endTimeRepresentation: {
                                            RelativeTimeText(date: endTime)
                                        }
                                    } else if let firstIngestionTime, timeDisplayStyle == .relativeToStart {
                                        if isFirstIngestion {
                                            TimeRangeRepresentation {
                                                Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            } endTimeRepresentation: {
                                                Text(endTime, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            }
                                        } else {
                                            let startTimeComponents = DateDifference.between(firstIngestionTime, and: ingestion.timeUnwrapped)
                                            let endTimeComponents = DateDifference.between(firstIngestionTime, and: endTime)
                                            TimeRangeRepresentation {
                                                Text(DateDifference.formattedWithMax2Units(startTimeComponents))
                                            } endTimeRepresentation: {
                                                Text(DateDifference.formattedWithMax2Units(endTimeComponents)) + Text(" after start")
                                            }
                                        }
                                    } else if timeDisplayStyle == .between {
                                        if isFirstIngestion {
                                            TimeRangeRepresentation {
                                                Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            } endTimeRepresentation: {
                                                Text(endTime, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            }
                                        } else if let previousIngestion {
                                            let startTimeComponents = DateDifference.between(previousIngestion.timeUnwrapped, and: ingestion.timeUnwrapped)
                                            let endTimeComponents = DateDifference.between(previousIngestion.timeUnwrapped, and: endTime)
                                            TimeRangeRepresentation {
                                                Text(DateDifference.formattedWithMax2Units(startTimeComponents))
                                            } endTimeRepresentation: {
                                                Text(DateDifference.formattedWithMax2Units(endTimeComponents)) + Text(" after last")
                                            }
                                        }
                                    } else {
                                        let isRangeWithinDay = ingestion.timeUnwrapped.asDateString == endTime.asDateString
                                        if isRangeWithinDay {
                                            TimeRangeRepresentation {
                                                Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            } endTimeRepresentation: {
                                                Text(endTime, format: Date.FormatStyle().hour().minute())
                                            }
                                        } else {
                                            TimeRangeRepresentation {
                                                Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            } endTimeRepresentation: {
                                                Text(endTime, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                            }
                                        }

                                    }
                                } else {
                                    if timeDisplayStyle == .relativeToNow {
                                        RelativeTimeText(date: ingestion.timeUnwrapped)
                                    } else if let firstIngestionTime, timeDisplayStyle == .relativeToStart {
                                        if isFirstIngestion {
                                            Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                        } else {
                                            let dateComponents = DateDifference.between(firstIngestionTime, and: ingestion.timeUnwrapped)
                                            Text(DateDifference.formattedWithMax2Units(dateComponents)) + Text(" after start")
                                        }
                                    } else if timeDisplayStyle == .between {
                                        if isFirstIngestion {
                                            Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                        } else if let previousIngestion {
                                            let dateComponents = DateDifference.between(previousIngestion.timeUnwrapped, and: ingestion.timeUnwrapped)
                                            Text(DateDifference.formattedWithMax2Units(dateComponents)) + Text(" after last")
                                        }
                                    } else {
                                        Text(ingestion.timeUnwrapped, format: Date.FormatStyle().hour().minute().weekday(.abbreviated))
                                    }
                                }
                            }
                        )
                        let isIngestionHidden = hiddenIngestions.contains(ingestion.id)
                        if isIngestionHidden {
                            Label("Hidden", systemImage: "eye.slash.fill").labelStyle(.iconOnly)
                        }
                    }
                }
                if isLastIngestion && isCurrentExperience {
                    if timeDisplayStyle == .between  {
                        TimelineView(.everyMinute) { _ in
                            Text("Last ingestion was ") + Text(ingestion.timeUnwrapped, style: .relative) + Text(" ago")
                        }
                    } else if timeDisplayStyle == .relativeToStart  {
                        TimelineView(.everyMinute) { _ in
                            Text("Now ") + Text(ingestion.timeUnwrapped, style: .relative) + Text(" after start")
                        }
                    }

                }
            }
        }
    }
}

struct TimeRangeRepresentation<TimeRepresentation: View>: View {

    @ViewBuilder let startTimeRepresentation: () -> TimeRepresentation
    @ViewBuilder let endTimeRepresentation: () -> TimeRepresentation

    var body: some View {
        HStack(spacing: 0) {
            startTimeRepresentation()
            Text(" - ")
            endTimeRepresentation()
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
