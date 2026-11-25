import Charts
import HealthKit
import SwiftUI

struct ExperienceHeartRateScreen: View {
    let window: DateInterval
    @State private var phase = HeartRatePhase.idle
    @State private var request: UUID?

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // Use recorded dates, never the durations drawn by the estimated effects chart.
    static func window(for experience: Experience, includesRatings: Bool = false, now: Date = .now) -> DateInterval? {
        let ingestionDates = experience.myIngestionsSorted.flatMap { [$0.time, $0.endTime].compactMap { $0 } }
        let noteDates = experience.timedNotesSorted.filter(\.isPartOfTimeline).compactMap(\.time)
        let ratingDates = includesRatings ? experience.ratingsWithTimeSorted.compactMap(\.time) : []
        let dates = ingestionDates + noteDates + ratingDates
        guard let start = dates.min(), let latest = dates.max(), start < now else { return nil }
        // A single timestamp needs a visible interval. The exact bounds appear before the read.
        let end = start == latest ? start.addingTimeInterval(3_600) : latest
        return DateInterval(start: start, end: min(end, now))
    }

    var body: some View {
        List {
            Section("Experience Window") {
                LabeledContent("From", value: window.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Through", value: window.end.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                if Self.isAvailable {
                    content
                } else {
                    Text("Apple Health is unavailable on this device.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Measured Heart Rate")
            } footer: {
                Text("Readings stay in this view and are excluded from journal exports and backups.")
            }
        }
        .navigationTitle("Heart Rate")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            guard request != nil else { return }
            await loadReadings()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Button("Read from Apple Health") { request = UUID() }
        case .loading:
            ProgressView("Reading from Apple Health…")
        case .failed:
            Text("Heart rate couldn’t be loaded.").foregroundStyle(.secondary)
            Button("Try Again") { request = UUID() }
        case .loaded(let readings):
            if readings.isEmpty {
                Text("No samples available").foregroundStyle(.secondary)
                Text("Check this date range and FreakLog’s access in Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(readings) { reading in
                    PointMark(
                        x: .value("Time", reading.time),
                        y: .value("Heart Rate", reading.beatsPerMinute)
                    )
                    .foregroundStyle(Color.pink)
                }
                .chartXScale(domain: window.start...window.end)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("bpm")
                .frame(height: 180)
                .privacySensitive()
                NavigationLink {
                    readingsList(readings)
                } label: {
                    LabeledContent("Readings", value: readings.count.formatted())
                }
            }
            Button("Refresh Readings") { request = UUID() }
        }
    }

    private func readingsList(_ readings: [HeartRateReading]) -> some View {
        List(readings) { reading in
            LabeledContent {
                Text("\(reading.beatsPerMinute, format: .number.precision(.fractionLength(0...1))) bpm")
            } label: {
                Text(reading.time, format: .dateTime.month().day().hour().minute().second())
                Text(reading.source)
            }
            .privacySensitive()
        }
        .navigationTitle("Readings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func loadReadings() async {
        await readHeartRate(in: window, phase: $phase)
    }
}

private struct HeartRateReading: Identifiable {
    let id: UUID
    let time: Date
    let beatsPerMinute: Double
    let source: String
}

private enum HeartRatePhase {
    case idle
    case loading
    case loaded([HeartRateReading])
    case failed
}

@MainActor
private func readHeartRate(in window: DateInterval, phase: Binding<HeartRatePhase>) async {
    phase.wrappedValue = .loading
    let healthStore = HKHealthStore()
    let type = HKQuantityType(.heartRate)
    do {
        try await healthStore.requestAuthorization(toShare: [], read: [type])
        try Task.checkCancellation()
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start, end: window.end, options: [.strictStartDate, .strictEndDate]
        )
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await query.result(for: healthStore)
        try Task.checkCancellation()
        let unit = HKUnit.count().unitDivided(by: .minute())
        let readings = samples.compactMap { sample -> HeartRateReading? in
            let beatsPerMinute = sample.quantity.doubleValue(for: unit)
            guard beatsPerMinute.isFinite, beatsPerMinute > 0 else { return nil }
            return HeartRateReading(
                id: sample.uuid, time: sample.startDate, beatsPerMinute: beatsPerMinute,
                source: sample.sourceRevision.source.name
            )
        }
        phase.wrappedValue = .loaded(readings)
    } catch is CancellationError {
        return
    } catch {
        guard !Task.isCancelled else { return }
        phase.wrappedValue = .failed
    }
}

struct HeartRateTimelineSection: View {
    let window: DateInterval
    let domain: ClosedRange<Date>
    let cursor: Date?

    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = HeartRatePhase.idle
    @State private var request: UUID?

    var body: some View {
        Section {
            switch phase {
            case .idle:
                Button {
                    request = UUID()
                } label: {
                    Label("Show Heart Rate", systemImage: "heart")
                }
            case .loading:
                ProgressView("Reading Apple Health…")
            case .failed:
                Text("Heart rate couldn’t be loaded.")
                    .foregroundStyle(.secondary)
                Button("Try Again") { request = UUID() }
            case .loaded(let readings):
                measuredReadings(readings)
                Button("Hide Heart Rate", action: clearReadings)
            }
        } header: {
            Text("Measured Heart Rate")
        } footer: {
            switch phase {
            case .idle:
                Text("Read Apple Health samples from this experience’s recorded window.")
            case .loaded:
                Text("Each point is an Apple Health sample. Empty intervals have no readings.")
            default:
                EmptyView()
            }
        }
        .task(id: request) {
            guard request != nil else { return }
            await readHeartRate(in: window, phase: $phase)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { clearReadings() }
        }
    }

    @ViewBuilder
    private func measuredReadings(_ readings: [HeartRateReading]) -> some View {
        if readings.isEmpty {
            Text("No heart rate samples in this experience.")
                .foregroundStyle(.secondary)
        } else {
            let plotted = readings.filter { domain.contains($0.time) }
            Chart {
                ForEach(plotted) { reading in
                    PointMark(
                        x: .value("Time", reading.time),
                        y: .value("Heart Rate", reading.beatsPerMinute)
                    )
                    .foregroundStyle(Color.pink)
                    .accessibilityLabel(Text(reading.time, format: .dateTime.hour().minute().second()))
                    .accessibilityValue(Text("\(reading.beatsPerMinute, format: .number.precision(.fractionLength(0...1))) bpm"))
                }
                if let cursor, domain.contains(cursor) {
                    RuleMark(x: .value("Selected Time", cursor))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: domain, range: .plotDimension(padding: 0))
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .overlay(alignment: .topLeading) {
                Text("bpm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .accessibilityHidden(true)
            }
            .frame(height: 92)
            .accessibilityLabel("Measured Heart Rate")
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .privacySensitive()
            if plotted.isEmpty {
                Text("No heart rate samples in this part of the timeline.")
                    .foregroundStyle(.secondary)
            } else if let low = plotted.map(\.beatsPerMinute).min(), let high = plotted.map(\.beatsPerMinute).max() {
                LabeledContent("Range") {
                    Text("\(low, format: .number.precision(.fractionLength(0...1)))–\(high, format: .number.precision(.fractionLength(0...1))) bpm")
                }
                    .privacySensitive()
            }
        }
    }

    private func clearReadings() {
        request = nil
        phase = .idle
    }
}
