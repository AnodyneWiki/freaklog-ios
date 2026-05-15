import SwiftUI

/// Compact, watchOS-friendly canvas-only timeline.
/// Reuses the shared TimelineModel + Drawables but skips iOS-only interactivity.
struct WatchTimelinePreview: View {
    let experience: Experience

    private var model: TimelineModel? {
        let ingestions = experience.myIngestionsSorted
        guard !ingestions.isEmpty else { return nil }
        return ExperienceLogic.timelineModel(
            from: ingestions,
            everythingForEachRating: [],
            everythingForEachTimedNote: [],
            areRedosesDrawnIndividually: false,
            areSubstanceHeightsIndependent: false
        )
    }

    var body: some View {
        if let model {
            TimelineView(.everyMinute) { timeline in
                Canvas { context, size in
                    let pixelsPerSec = size.width / model.totalWidth
                    model.groupDrawables.forEach {
                        $0.draw(context: context, height: size.height, pixelsPerSec: pixelsPerSec, lineWidth: 3)
                    }
                    let nowSecs = timeline.date.timeIntervalSince(model.startTime)
                    if nowSecs > 0 && nowSecs < model.totalWidth {
                        let x = nowSecs * pixelsPerSec
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.primary.opacity(0.6)), lineWidth: 1)
                    }
                }
            }
        } else {
            Color.clear
        }
    }
}
