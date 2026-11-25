import SwiftUI

struct TimePointOrRangePicker: View {

    @Binding var selectedTimePickerOption: TimePickerOption
    @Binding var selectedTime: Date
    @Binding var selectedEndTime: Date
    var showsPresets = false

    var body: some View {
        Picker("Time picker option", selection: $selectedTimePickerOption.animation()) {
            Text("Time point").tag(TimePickerOption.pointInTime)
            Text("Time range").tag(TimePickerOption.timeRange)
        }.pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: selectedTimePickerOption) { newValue in
            if newValue == .timeRange, selectedEndTime < selectedTime || selectedTime.distance(to: selectedEndTime) > 24*60*60 {
                selectedEndTime = selectedTime.addingTimeInterval(30*60)
            }
        }
        if showsPresets {
            timePresets
        }
        switch selectedTimePickerOption {
        case .pointInTime:
            HStack(alignment: .center) {
                DatePicker(
                    "Time",
                    selection: $selectedTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                if !showsPresets {
                    Spacer()
                    Button {
                        withAnimation {
                            selectedTime = Date.now
                        }
                    } label: {
                        Label("Reset time", systemImage: "clock.arrow.circlepath").labelStyle(.iconOnly)
                    }
                }
            }
        case .timeRange:
            DatePicker(
                "Start time",
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
                "End time",
                selection: Binding(get: {
                    selectedEndTime
                }, set: { newEnd in
                    selectedEndTime = newEnd
                    if newEnd < selectedTime {
                        selectedTime = newEnd.addingTimeInterval(-30*60)
                    }
                }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
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
                    Text("Set Start Time")
                } else {
                    Text("Set Time")
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
