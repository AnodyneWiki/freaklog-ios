import SwiftUI

struct DayView: View {
    let date: Date
    let ingestions: [Ingestion]
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.day())
                    .fontWeight(isSelected || Calendar.current.isDateInToday(date) ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : (ingestions.isEmpty ? Color.secondary : Color.primary))
                Group {
                    if ingestions.isEmpty {
                        Color.clear
                    } else {
                        CalendarColorRectangle(colors: ingestions.map { $0.substanceColor.swiftUIColor })
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 5)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month().day().year()))
        .accessibilityValue(ingestions.count.formatted())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
