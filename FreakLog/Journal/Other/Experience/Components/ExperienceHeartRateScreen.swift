import Charts
import HealthKit
import SwiftUI

struct HeartRateWindow: Equatable {
    let start: Date
    let lastRecordedTime: Date

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func recorded(in experience: Experience, includesRatings: Bool) -> Self? {
        let ingestions = experience.myIngestionsSorted.filter { !$0.isUnconfirmed && !$0.isHiddenFromTimeline }
        let ingestionDates = ingestions.flatMap { [$0.time, $0.endTime].compactMap { $0 } }
        let noteDates = experience.timedNotesSorted.filter(\.isPartOfTimeline).compactMap(\.time)
        let ratingDates = includesRatings
            ? experience.ratingsWithTimeSorted.filter { !$0.isHiddenInTimeline }.compactMap(\.time)
            : []
        let dates = ingestionDates + noteDates + ratingDates
        guard let start = dates.min(), let end = dates.max(), start < .now else { return nil }
        return Self(start: start, lastRecordedTime: end)
    }

    func interval(through now: Date) -> DateInterval? {
        guard start < now else { return nil }
        // A single recorded time has no duration to query, so offer one hour following it.
        let end = lastRecordedTime > start ? lastRecordedTime : start.addingTimeInterval(3_600)
        return DateInterval(start: start, end: min(end, now))
    }
}

struct HeartRateReading: Identifiable {
    let id: UUID
    let time: Date
    let beatsPerMinute: Double
    let source: String
    let wasManuallyEntered: Bool

    var sourceLabel: Text {
        wasManuallyEntered ? Text("\(source) · Entered Manually") : Text(source)
    }

    var valueLabel: Text {
        Text("\(beatsPerMinute, format: .number.precision(.fractionLength(0...1))) bpm")
    }
}

struct HeartRateSeries {
    let readings: [HeartRateReading]
    let valueDomain: ClosedRange<Double>

    init(_ readings: [HeartRateReading]) {
        self.readings = readings.sorted { $0.time < $1.time }
        let values = readings.map(\.beatsPerMinute)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let padding = max((maximum - minimum) * 0.05, 1)
        valueDomain = max(0, minimum - padding)...(maximum + padding)
    }

    func visible(in domain: ClosedRange<Date>) -> ArraySlice<HeartRateReading> {
        readings[boundary { $0 < domain.lowerBound }..<boundary { $0 <= domain.upperBound }]
    }

    func nearest(to time: Date, in domain: ClosedRange<Date>, within limit: TimeInterval) -> HeartRateReading? {
        let visible = visible(in: domain)
        let index = boundary { $0 < time }
        let older = visible.indices.contains(index - 1) ? readings[index - 1] : nil
        let newer = visible.indices.contains(index) ? readings[index] : nil
        let nearest = [older, newer].compactMap { $0 }.min {
            abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
        }
        guard let nearest, abs(nearest.time.timeIntervalSince(time)) <= limit else { return nil }
        return nearest
    }

    private func boundary(while precedes: (Date) -> Bool) -> Int {
        var lower = 0
        var upper = readings.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if precedes(readings[middle].time) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

struct HeartRateTimelineSection: View {
    let window: HeartRateWindow
    let domain: ClosedRange<Date>?
    let cursor: Date?
    let selectTime: (Date) -> Void
    var fullWidthPlot = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = HeartRatePhase.idle
    @State private var request: DateInterval?

    var body: some View {
        Section {
            switch phase {
            case .idle:
                Button(action: load) {
                    Label("Show Heart Rate", systemImage: "heart")
                }
            case .loading:
                ProgressView("Reading Apple Health…")
            case .unavailable:
                Text("Unlock this device to read from Apple Health.")
                    .foregroundStyle(.secondary)
                Button("Try Again", action: load)
            case .failed:
                Text("Heart rate couldn’t be loaded.")
                    .foregroundStyle(.secondary)
                Button("Try Again", action: load)
            case .loaded(let interval, let series):
                if scenePhase == .active {
                    measuredReadings(series, interval: interval)
                    HStack {
                        Button("Hide", action: clearReadings)
                            .accessibilityLabel("Hide Heart Rate")
                        Spacer()
                        Button(action: load) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh Heart Rate")
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
        } header: {
            if case .idle = phase {
                EmptyView()
            } else {
                Text("Heart Rate")
            }
        } footer: {
            if case .idle = phase, let proposedWindow = window.interval(through: .now) {
                Text("Read from Apple Health for \(dateRange(proposedWindow)). Samples stay on this screen.")
            }
        }
        .task(id: request) {
            guard let request else { return }
            await readHeartRate(in: request)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { clearReadings() }
        }
        .onChange(of: window) { _ in clearReadings() }
    }

    @ViewBuilder
    private func measuredReadings(_ series: HeartRateSeries, interval: DateInterval) -> some View {
        if series.readings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No Samples Available")
                Text("Check these dates and FreakLog’s Heart Rate access in Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Read Window", value: dateRange(interval))
        } else {
            let plotDomain = domain ?? interval.start...interval.end
            let visible = series.visible(in: plotDomain)
            if visible.isEmpty {
                Text("No samples in this part of the timeline.")
                    .foregroundStyle(.secondary)
            } else {
                HeartRateChart(
                    series: series, visible: visible, domain: plotDomain,
                    cursor: cursor, showsTimeAxis: domain == nil, selectTime: selectTime
                )
                .listRowInsets(fullWidthPlot ? EdgeInsets(top: 8, leading: 0, bottom: 6, trailing: 0) : nil)
                if let low = visible.map(\.beatsPerMinute).min(), let high = visible.map(\.beatsPerMinute).max() {
                    LabeledContent("Visible Range") {
                        if low == high {
                            Text("\(low, format: .number.precision(.fractionLength(0...1))) bpm")
                        } else {
                            Text("\(low, format: .number.precision(.fractionLength(0...1)))–\(high, format: .number.precision(.fractionLength(0...1))) bpm")
                        }
                    }
                    .privacySensitive()
                }
                if let cursor, plotDomain.contains(cursor) {
                    if let sample = series.nearest(to: cursor, in: plotDomain, within: 60) {
                        readingRow(sample, title: sample.time == cursor ? "At Cursor" : "Near Cursor")
                    } else {
                        Text("No sample within a minute of the cursor.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                ExperienceHeartRateScreen {
                    guard case .loaded(_, let current) = phase else { return [] }
                    return current.readings
                }
            } label: {
                LabeledContent("All Samples", value: series.readings.count.formatted())
            }
        }
    }

    private func load() {
        guard let interval = window.interval(through: .now) else { return }
        request = interval
    }

    private func clearReadings() {
        request = nil
        phase = .idle
    }

    @MainActor
    private func readHeartRate(in interval: DateInterval) async {
        phase = .loading
        defer {
            if !Task.isCancelled, request == interval { request = nil }
        }
        let healthStore = HKHealthStore()
        let type = HKQuantityType(.heartRate)
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [type])
            try Task.checkCancellation()
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start, end: interval.end, options: [.strictStartDate, .strictEndDate]
            )
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await query.result(for: healthStore)
            try Task.checkCancellation()
            guard request == interval else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let readings = samples.compactMap { sample -> HeartRateReading? in
                let beatsPerMinute = sample.quantity.doubleValue(for: unit)
                guard beatsPerMinute.isFinite, beatsPerMinute > 0 else { return nil }
                return HeartRateReading(
                    id: sample.uuid, time: sample.startDate, beatsPerMinute: beatsPerMinute,
                    source: sample.sourceRevision.source.name,
                    wasManuallyEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true
                )
            }
            phase = .loaded(interval, HeartRateSeries(readings))
        } catch {
            guard request == interval, !Task.isCancelled else { return }
            if let error = error as? HKError {
                switch error.code {
                case .errorDatabaseInaccessible: phase = .unavailable
                case .errorUserCanceled: phase = .idle
                case .errorNoData: phase = .loaded(interval, HeartRateSeries([]))
                default: phase = .failed
                }
            } else {
                phase = .failed
            }
        }
    }

    private func dateRange(_ interval: DateInterval) -> String {
        (interval.start..<interval.end).formatted(.interval.year().month(.abbreviated).day().hour().minute())
    }
}

private enum HeartRatePhase {
    case idle
    case loading
    case loaded(DateInterval, HeartRateSeries)
    case unavailable
    case failed
}

private struct ExperienceHeartRateScreen: View {
    let readings: () -> [HeartRateReading]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if scenePhase == .active {
                let activeReadings = readings()
                if activeReadings.isEmpty {
                    Text("Read from Apple Health again to see your samples.")
                        .foregroundStyle(.secondary)
                }
                ForEach(activeReadings) { reading in
                    readingRow(reading)
                }
            }
        }
        .navigationTitle("Heart Rate Samples")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func readingRow(_ reading: HeartRateReading, title: LocalizedStringKey? = nil) -> some View {
    LabeledContent {
        reading.valueLabel.monospacedDigit()
    } label: {
        if let title {
            Text(title)
        }
        Text(reading.time, format: .dateTime.month().day().hour().minute().second())
        reading.sourceLabel
    }
    .privacySensitive()
}

private struct HeartRateChart: View {
    let series: HeartRateSeries
    let visible: ArraySlice<HeartRateReading>
    let domain: ClosedRange<Date>
    let cursor: Date?
    let showsTimeAxis: Bool
    let selectTime: (Date) -> Void

    var body: some View {
        let selected = cursor.flatMap { time in
            domain.contains(time) ? series.nearest(to: time, in: domain, within: 60) : nil
        }
        Chart {
            ForEach(visible) { reading in
                PointMark(x: .value("Time", reading.time), y: .value("Heart Rate", reading.beatsPerMinute))
                    .symbolSize(reading.id == selected?.id ? 54 : 20)
                    .foregroundStyle(Color.pink)
                    .accessibilityLabel(Text(reading.time, format: .dateTime.hour().minute().second()))
                    .accessibilityValue(Text("\(reading.valueLabel), \(reading.sourceLabel)"))
            }
            if let cursor, domain.contains(cursor) {
                RuleMark(x: .value("Selected Time", cursor))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: domain, range: .plotDimension(padding: 0))
        .chartYScale(domain: series.valueDomain)
        .chartXAxis(showsTimeAxis ? .automatic : .hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = if #available(iOS 17.0, *) {
                    proxy.plotFrame.map { geometry[$0] } ?? .zero
                } else {
                    geometry[proxy.plotAreaFrame]
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard plot.contains(tap.location), plot.width > 0,
                              let time = proxy.value(atX: tap.location.x - plot.minX, as: Date.self) else { return }
                        let hitRadius = domain.upperBound.timeIntervalSince(domain.lowerBound) * 18 / plot.width
                        if let reading = series.nearest(to: time, in: domain, within: hitRadius) {
                            selectTime(reading.time)
                        }
                    })
                    .accessibilityHidden(true)
            }
        }
        .frame(height: showsTimeAxis ? 150 : 112)
        .accessibilityLabel("Apple Health Heart Rate")
        .accessibilityValue(selected?.valueLabel ?? Text("No sample selected"))
        .accessibilityAdjustableAction { direction in
            let next: HeartRateReading?
            switch direction {
            case .increment:
                next = cursor.map { time in visible.first { $0.time > time } } ?? visible.first
            case .decrement:
                next = cursor.map { time in visible.last { $0.time < time } } ?? visible.last
            @unknown default:
                next = nil
            }
            if let next { selectTime(next.time) }
        }
        .privacySensitive()
    }
}
