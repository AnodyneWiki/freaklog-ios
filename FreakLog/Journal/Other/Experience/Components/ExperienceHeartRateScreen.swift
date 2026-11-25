import Charts
import HealthKit
import SwiftUI

struct ExperienceHeartRateScreen: View {
    private struct Reading: Identifiable {
        let id: UUID
        let time: Date
        let beatsPerMinute: Double
        let source: String
    }

    private enum Phase {
        case idle
        case loading
        case loaded([Reading])
        case failed
    }

    let window: DateInterval
    @State private var phase = Phase.idle
    @State private var didRequestReadings = false
    @State private var healthStore = HKHealthStore()

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
        .task(id: didRequestReadings) {
            guard didRequestReadings else { return }
            await loadReadings()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Button("Read from Apple Health") { didRequestReadings = true }
        case .loading:
            ProgressView("Reading from Apple Health…")
        case .failed:
            Text("Heart rate couldn’t be loaded.").foregroundStyle(.secondary)
            Button("Try Again") { didRequestReadings = true }
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
            Button("Refresh Readings") { didRequestReadings = true }
        }
    }

    private func readingsList(_ readings: [Reading]) -> some View {
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
        defer { didRequestReadings = false }
        guard Self.isAvailable else { return }
        phase = .loading
        let type = HKQuantityType(.heartRate)
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [type])
            try Task.checkCancellation()
            let predicate = HKQuery.predicateForSamples(
                withStart: window.start,
                end: window.end,
                options: [.strictStartDate, .strictEndDate]
            )
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await query.result(for: healthStore)
            try Task.checkCancellation()
            let unit = HKUnit.count().unitDivided(by: .minute())
            let readings = samples.compactMap { sample -> Reading? in
                let beatsPerMinute = sample.quantity.doubleValue(for: unit)
                guard beatsPerMinute.isFinite, beatsPerMinute > 0 else { return nil }
                return Reading(
                    id: sample.uuid,
                    time: sample.startDate,
                    beatsPerMinute: beatsPerMinute,
                    source: sample.sourceRevision.source.name
                )
            }
            phase = .loaded(readings)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed
        }
    }
}
