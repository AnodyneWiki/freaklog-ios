import SwiftUI

struct TimelineSection: View {
    let timelineModel: TimelineModel
    let editIngestion: (Ingestion) -> Void
    let ingestionsSorted: [Ingestion]
    let timeDisplayStyle: TimeDisplayStyle
    let isEyeOpen: Bool
    let isHidingDosageDots: Bool
    let hiddenIngestions: Set<ObjectIdentifier>
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
                                EventTimeText(
                                    time: ingestion.timeUnwrapped,
                                    endTime: ingestion.endTime,
                                    style: timeDisplayStyle,
                                    firstIngestionTime: firstIngestionTime,
                                    previousTime: previousIngestion?.timeUnwrapped,
                                    isIngestion: true
                                )
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

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
