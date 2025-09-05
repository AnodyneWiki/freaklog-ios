import SwiftUI

struct TimedNoteDottedLine: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: size.height))
            path.addLine(to: CGPoint(x: size.width / 2, y: 0))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle.getTimedNoteStokeStyle()
            )
        }
        .frame(width: StrokeStyle.timedNoteLineWidth)
    }
}

#Preview {
    TimedNoteDottedLine(color: .blue)
}
