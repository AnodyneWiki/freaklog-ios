import SwiftUI

struct ExperienceTimeText: View {
    let time: Date
    let timeDisplayStyle: SaveableTimeDisplayStyle
    let isCurrent: Bool

    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey)
    private var dynamicRange = DynamicRangeOption.twentyFourHours

    var body: some View {
        let style = timeDisplayStyle.resolved(isCurrent: isCurrent || dynamicRange.containsRecent(time))
        if isCurrent {
            if time < .now {
                return Text("Active since ") + Text(time, style: .relative)
            } else {
                return Text(time, style: .relative)
            }
        } else {
            if style == .relativeToNow {
                return Text(time, format: .relative(presentation: .numeric, unitsStyle: .wide))
            } else {
                return Text(time, format: Date.FormatStyle().day().month().year().weekday(.abbreviated))
            }
        }
    }
}

#Preview {
    ExperienceTimeText(time: Date() - 5 * 60 * 60 - 30, timeDisplayStyle: .regular, isCurrent: true)
}
