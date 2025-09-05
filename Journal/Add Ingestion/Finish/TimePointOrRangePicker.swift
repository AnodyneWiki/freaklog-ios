import SwiftUI

struct TimePointOrRangePicker: View {

    @Binding var selectedTimePickerOption: TimePickerOption
    @Binding var selectedTime: Date
    @Binding var selectedEndTime: Date

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
        switch selectedTimePickerOption {
        case .pointInTime:
            HStack(alignment: .center) {
                DatePicker(
                    "Time",
                    selection: $selectedTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                Spacer()
                Button {
                    withAnimation {
                        selectedTime = Date.now
                    }
                } label: {
                    Label("Reset time", systemImage: "clock.arrow.circlepath").labelStyle(.iconOnly)
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
}

enum TimePickerOption {
    case pointInTime, timeRange
}
