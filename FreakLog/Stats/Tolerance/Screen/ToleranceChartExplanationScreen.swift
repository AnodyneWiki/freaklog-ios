import SwiftUI

struct ToleranceChartExplanationScreen: View {
    var body: some View {
        List {
            Section("Limitations") {
                Text("""
                This chart represents the time it would take for a full tolerance, established at the time of ingestion, to decrease to half and ultimately to none.

                The chart assumes instant full tolerance with each ingestion, acting as a basic reference. However for many substances, full tolerance doesn't happen immediately but builds up with prolonged and repeated use. For more nuanced details regarding the tolerance of a specific substance, refer to the corresponding article on PsychonautWiki.

                Other influencing factors, like the doses consumed and potential cross-tolerances, are not considered.
                """)
            }

            Section("Understanding the Visualization") {
                Text("""
                Marked by an opaque hue, the phase directly succeeding consumption reflects an elevated tolerance to the particular substance. The subsequent lighter shade indicates a reduced tolerance level. This is followed by a return to zero tolerance, necessitating dosage adjustments akin to initial consumption.

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
