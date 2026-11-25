import SwiftUI

struct ToleranceChartExplanationScreen: View {
    var body: some View {
        List {
            Section("Limitations") {
                Text("""
                This chart represents the time it would take for a full tolerance, established at the time of ingestion, to decrease to half and ultimately to none.

                The chart assumes instant full tolerance with each ingestion, acting as a basic reference. However for many substances, full tolerance doesn't happen immediately but builds up with prolonged and repeated use. For more nuanced details regarding the tolerance of a specific substance, refer to the corresponding article on PsychonautWiki.

                The chart uses confirmed entries. It leaves out doses and possible cross-tolerance. Cross-Tolerance Evidence lists studied pairs separately.
                """)
            }

            Section("Understanding the Visualization") {
                Text("""
                The darker color marks the estimated full-tolerance interval. The lighter color marks the estimated half-tolerance interval. These intervals describe the chart's assumptions, and their end does not establish a person's tolerance.

                The 'start date' denotes the earliest ingestion taken into consideration.

                The vertical line marks the present time. The gray vertical line marks the time at which an experience took place if the chart appears within an experience.
                """)
            }
        }
        .navigationTitle("Chart Limitations")
    }
}

#Preview {
    NavigationStack {
        ToleranceChartExplanationScreen()
    }
}
