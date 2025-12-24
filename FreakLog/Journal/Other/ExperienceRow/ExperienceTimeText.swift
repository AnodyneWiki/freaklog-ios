import SwiftUI

struct ExperienceTimeText: View {
    let time: Date
    let timeDisplayStyle: SaveableTimeDisplayStyle
    let isCurrent: Bool

    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) private var dynamicExperienceRangeHours: Int = 24

    var body: some View {
        let style: TimeDisplayStyle = {
            switch timeDisplayStyle {
            case .regular: return .regular
            case .relativeToNow: return .relativeToNow
            case .relativeToStart: return .relativeToStart
            case .between: return .between
            case .auto:
                if isCurrent {
                    return .relativeToNow
                } else {
                    // Auto logic: relative if recent (within dynamic range), otherwise regular
                    let window = TimeInterval(dynamicExperienceRangeHours) * 60 * 60
                    if time > Date.now.addingTimeInterval(-window) {
                        return .relativeToNow
                    } else {
                        return .regular
                    }
                }
            }
        }()

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
