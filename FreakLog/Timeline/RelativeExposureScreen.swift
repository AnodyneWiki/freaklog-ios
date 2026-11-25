import Charts
import SwiftUI

private struct CaffeineExposureScenario: Identifiable {
    private static let peakHours = 29.8 / 60
    private static let durationHours = 24.0
    private static let ln2 = log(2.0)

    let halfLifeHours: Double
    let label: String
    let dash: [CGFloat]
    var id: Double { halfLifeHours }

    static let observedExtremes = [
        Self(halfLifeHours: 2.7, label: "Shorter study half-life", dash: []),
        Self(halfLifeHours: 9.9, label: "Longer study half-life", dash: [5, 4])
    ]

    struct Point: Identifiable {
        let hour: Double
        let relativeExposure: Double
        var id: Double { hour }
    }

    var points: [Point] {
        let elimination = Self.ln2 / halfLifeHours
        let absorption = Self.absorptionRate(elimination: elimination)
        func curve(at hour: Double) -> Double {
            exp(-elimination * hour) - exp(-absorption * hour)
        }
        let peak = curve(at: Self.peakHours)
        let hours = (Array(stride(from: 0.0, through: Self.durationHours, by: 0.125)) + [Self.peakHours]).sorted()
        return hours.map { hour in
            Point(hour: hour, relativeExposure: curve(at: hour) / peak)
        }
    }

    private static func absorptionRate(elimination: Double) -> Double {
        // Solve tPeak = ln(ka / ke) / (ka - ke) for first-order absorption.
        var low = elimination + 0.00001
        var high = 100.0
        for _ in 0..<40 {
            let middle = (low + high) / 2
            let peak = log(middle / elimination) / (middle - elimination)
            if peak > peakHours {
                low = middle
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }
}

struct RelativeExposureScreen: View {
    let ingestions: [Ingestion]

    @State private var selectedEntry: Ingestion.ID?
    @State private var confirmsSolution = false

    private var candidates: [Ingestion] {
        ingestions.filter { entry in
            entry.isMine && !entry.isUnconfirmed && !entry.isHiddenFromTimeline
                && entry.substanceNameUnwrapped == "Caffeine" && entry.administrationRouteUnwrapped == .oral
                && entry.time != nil && entry.endTime == nil && !entry.isEstimate && entry.formulation == nil
                && (entry.pureSubstanceDose.map { $0.isFinite && $0 > 0 } ?? false)
        }
    }

    private var selected: Ingestion? {
        candidates.first { $0.id == selectedEntry }
    }

    var body: some View {
        List {
            Section {
                if candidates.isEmpty {
                    Text("No eligible caffeine entries in this experience.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Journal Entry", selection: $selectedEntry) {
                        Text("Choose Entry").tag(nil as Ingestion.ID?)
                        ForEach(candidates) { entry in
                            Text(entry.timeUnwrapped, format: TimelineCursorEntry.dateFormat)
                                .tag(Optional(entry.id))
                        }
                    }
                    if selected != nil {
                        Toggle("Taken as a single aqueous solution", isOn: $confirmsSolution)
                    }
                }
            } footer: {
                Text("The study modeled here used a single dose of caffeine dissolved in water. Choose an entry only if that matches the form recorded. Other forms, repeated doses, and unconfirmed or unknown amounts are outside this model.")
            }
            if let selected, confirmsSolution {
                modelSection(for: selected.timeUnwrapped)
            }
            Section("Research") {
                Link("Blanchard & Sawers, 1983", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/6832208/")!)
                Text("The study analyzed blood samples from ten healthy young men. Each curve peaks near 30 minutes and uses one observed extreme of elimination half-life. The two curves illustrate variability in the study. They do not bound the response of an individual.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Modeled Exposure")
        .onChange(of: selectedEntry) { _ in confirmsSolution = false }
    }

    private func modelSection(for date: Date) -> some View {
        Section {
            LabeledContent("Journal Time") {
                Text(date, format: TimelineCursorEntry.dateFormat)
            }
            Chart(CaffeineExposureScenario.observedExtremes) { scenario in
                ForEach(scenario.points) { point in
                    LineMark(
                        x: .value("Hours Since Entry", point.hour),
                        y: .value("Relative Exposure", point.relativeExposure),
                        series: .value("Scenario", scenario.label)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: scenario.dash))
                    .accessibilityLabel(Text(scenario.label))
                    .accessibilityValue(Text("\(point.relativeExposure.formatted(.percent.precision(.fractionLength(0)))) at \(point.hour.formatted(.number.precision(.fractionLength(0...1)))) hours"))
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0.0, 0.5, 1.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) { Text(fraction, format: .percent) }
                    }
                }
            }
            .chartXAxisLabel("Hours Since Entry")
            .frame(height: 190)
            Label("Shorter study half-life (solid)", systemImage: "line.diagonal")
            Label("Longer study half-life (dashed)", systemImage: "line.diagonal")
        } header: {
            Text("Relative Caffeine Exposure")
        } footer: {
            Text("Each modeled curve is scaled to its own peak. The percentage is a relative model value and gives neither a blood concentration nor a measure of effects.")
        }
    }
}
