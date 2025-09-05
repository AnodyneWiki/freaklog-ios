import SwiftUI

struct ExperienceTimeText: View {
    let time: Date
    let isTimeRelative: Bool
    let isCurrent: Bool

    var body: some View {
        if isCurrent {
            if time < .now {
                return Text("Active since ") + Text(time, style: .relative)
            } else {
                return Text(time, style: .relative)
            }
        } else {
            if isTimeRelative {
                return Text(time, format: .relative(presentation: .numeric, unitsStyle: .wide))
            } else {
                return Text(time, format: Date.FormatStyle().day().month().year().weekday(.abbreviated))
            }
        }
    }
}

#Preview {
    ExperienceTimeText(time: Date() - 5 * 60 * 60 - 30, isTimeRelative: false, isCurrent: true)
}
