import SwiftUI

struct TimePointOrRangePicker: View {

    @Binding var selectedTimePickerOption: TimePickerOption
    @Binding var selectedTime: Date
    @Binding var selectedEndTime: Date
    var showsPresets = false

    var body: some View {
        Toggle("Time Range", isOn: Binding(
            get: { selectedTimePickerOption == .timeRange },
            set: { isRange in
                if isRange, selectedEndTime < selectedTime || selectedTime.distance(to: selectedEndTime) > 24 * 60 * 60 {
                    selectedEndTime = selectedTime.addingTimeInterval(30 * 60)
                }
                selectedTimePickerOption = isRange ? .timeRange : .pointInTime
            }
        ))
        switch selectedTimePickerOption {
        case .pointInTime:
            DatePicker(
                "Time",
                selection: $selectedTime,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
        case .timeRange:
            DatePicker(
                "Start",
                selection: Binding(get: {
                    selectedTime
                }, set: { newStart in
                    selectedTime = newStart
                    if newStart > selectedEndTime || newStart.distance(to: selectedEndTime) > 24*60*60 {
                        selectedEndTime = newStart.addingTimeInterval(30*60)
                    }
                }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            DatePicker(
                "End",
                selection: Binding(get: {
                    max(selectedTime, selectedEndTime)
                }, set: { newEnd in
                    selectedEndTime = newEnd
                }),
                in: selectedTime...max(selectedEndTime, selectedTime.addingTimeInterval(24 * 60 * 60)),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
        }
        if showsPresets {
            timePresets
        } else if selectedTimePickerOption == .pointInTime {
            Button("Set to Now") { selectedTime = .now }
        }
    }

    private var timePresets: some View {
        Menu {
            Button("Now") { applyTimePreset(minutesAgo: 0) }
            Button("15 minutes ago") { applyTimePreset(minutesAgo: 15) }
            Button("30 minutes ago") { applyTimePreset(minutesAgo: 30) }
            Button("1 hour ago") { applyTimePreset(minutesAgo: 60) }
            Button("2 hours ago") { applyTimePreset(minutesAgo: 120) }
        } label: {
            Label {
                if selectedTimePickerOption == .timeRange {
                    Text("Set Start Quickly")
                } else {
                    Text("Set Time Quickly")
                }
            } icon: {
                Image(systemName: "clock")
            }
        }
    }

    private func applyTimePreset(minutesAgo: Int) {
        let newStart = Date.now.addingTimeInterval(-Double(minutesAgo) * 60)
        if selectedTimePickerOption == .timeRange {
            let duration = max(0, selectedEndTime.timeIntervalSince(selectedTime))
            selectedEndTime = newStart.addingTimeInterval(duration)
        }
        selectedTime = newStart
    }
}

enum TimePickerOption {
    case pointInTime, timeRange
}
