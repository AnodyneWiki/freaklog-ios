import SwiftUI

struct TimeRangePicker: View {
    @Binding var value: TimeRange

    var body: some View {
        Picker("Time Range", selection: $value.animation(.easeInOut)) {
            Text("30 Days").tag(TimeRange.last30Days)
            Text("12 Months").tag(TimeRange.last12Months)
            Text("Years").tag(TimeRange.years)
        }
        .pickerStyle(.segmented)
    }
}
