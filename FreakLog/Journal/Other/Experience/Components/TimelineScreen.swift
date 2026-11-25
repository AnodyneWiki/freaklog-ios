import SwiftUI

struct TimelineScreen: View {
    let timelineModel: TimelineModel
    let timeDisplayStyle: TimeDisplayStyle
    @State private var zoomLevel = 1.0
    @State private var isOrientationLandscape = false
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false

    var body: some View {
        VStack {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack {
                        Spacer()
                        EffectTimeline(
                            timelineModel: timelineModel,
                            height: isOrientationLandscape ? geo.size.height : 300,
                            timeDisplayStyle: timeDisplayStyle
                        )
                        .frame(width: geo.size.width * zoomLevel)
                        Spacer()
                    }
                }
            }
            Slider(value: $zoomLevel, in: 1 ... 6) {
                Text("Zoom Level")
            }
            .padding(.bottom, isOrientationLandscape ? 0 : 100)
            .padding(.horizontal, 30)
        }
        .padding(.horizontal)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            checkCurrentOrientation()
        }
        .onAppear {
            checkCurrentOrientation()
        }
        .navigationTitle("Dose Response")
        .toolbar {
            if isEyeOpen {
                NavigationLink(value: GlobalNavigationDestination.explainExperience) {
                    Label("Timeline Limitations", systemImage: "info.circle")
                }
            }
        }
    }

    private func checkCurrentOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
            isOrientationLandscape = true
        } else if deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown {
            isOrientationLandscape = false
        }
    }
}

// The expanded view of a saved experience uses the same cursor as the preview.
struct ExperienceTimelineScreen: View {
    @ObservedObject var experience: Experience
    @Binding var selection: Date?

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var storedTimeStyle: SaveableTimeDisplayStyle = .auto
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var drawsRedosesIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var usesIndependentHeights = true
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false
    @AppStorage(TimelineModel.combinesComparableRoutesKey) private var combinesRoutes = false

    var body: some View {
        let model = experience.getMyTimeLineModel(
            areRedosesDrawnIndividually: drawsRedosesIndividually,
            areSubstanceHeightsIndependent: usesIndependentHeights,
            combinesComparableRoutes: combinesRoutes
        )
        TimelineCursorContent(
            experience: experience,
            model: model,
            entries: recordedEntries.filter { model.timeRange.contains($0.time) },
            timeDisplayStyle: storedTimeStyle.resolved(isCurrent: experience.isCurrent),
            showsLimitations: isEyeOpen,
            selection: $selection,
            combinesRoutes: $combinesRoutes
        )
        .observeExperienceTimeline(experience)
    }

    private var recordedEntries: [TimelineCursorEntry] {
        let ingestions = experience.myIngestionsSorted.compactMap { ingestion -> TimelineCursorEntry? in
            guard let date = ingestion.time, !ingestion.isHiddenFromTimeline, !ingestion.isUnconfirmed else { return nil }
            return TimelineCursorEntry(id: ingestion.id, time: date, title: ingestion.substanceDisplayName, icon: "pills")
        }
        let notes = experience.timedNotesSorted.compactMap { note -> TimelineCursorEntry? in
            guard let date = note.time, note.isPartOfTimeline else { return nil }
            return TimelineCursorEntry(id: note.id, time: date, title: note.noteUnwrapped, icon: "note.text")
        }
        let ratings = isEyeOpen ? experience.ratingsWithTimeSorted.compactMap { rating -> TimelineCursorEntry? in
            guard let date = rating.time, !rating.isHiddenInTimeline else { return nil }
            return TimelineCursorEntry(id: rating.id, time: date, title: "Rating \(rating.optionUnwrapped.stringRepresentation)", icon: "plus.forwardslash.minus")
        } : []
        return (ingestions + notes + ratings).sorted { $0.time < $1.time }
    }

}

private struct TimelineCursorContent: View {
    let experience: Experience
    let model: TimelineModel
    let entries: [TimelineCursorEntry]
    let timeDisplayStyle: TimeDisplayStyle
    let showsLimitations: Bool

    @Binding var selection: Date?
    @Binding var combinesRoutes: Bool
    @State private var noteTime: NoteTime?
    @State private var reminder: JournalReminderDraft?
    @State private var showsRecordedEntries = false
    @State private var zoom = 1
    @Namespace private var zoomAnchor
    @Namespace private var plotViewport
    @State private var visibleStartFraction = 0.0
    @AppStorage(TimelineModel.showsQuantityDetailsKey) private var showsQuantityDetails = true

    private var selectedTime: Date {
        model.clampingTime(selection ?? entries.first?.time ?? model.startTime)
    }

    private var visibleTimeRange: ClosedRange<Date> {
        let duration = max(1, model.totalWidth)
        let span = duration / Double(zoom)
        let offset = zoom == 1 ? 0 : min(max(0, visibleStartFraction * duration), duration - span)
        let start = model.startTime.addingTimeInterval(offset)
        return start...start.addingTimeInterval(span)
    }

    var body: some View {
        ScrollViewReader { scroll in
            List {
                cursorSection
                if HeartRateWindow.isAvailable,
                   let window = HeartRateWindow.recorded(in: experience, includesRatings: showsLimitations) {
                    HeartRateTimelineSection(
                        window: window,
                        domain: visibleTimeRange,
                        cursor: selectedTime,
                        selectTime: { selection = $0 },
                        fullWidthPlot: true
                    )
                }
                if let nearest = entries.min(by: {
                    abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime))
                }) {
                    Section {
                        ForEach(entries.filter { $0.time == nearest.time }) { entry in
                            entry.label
                        }
                    } header: {
                        Text(nearest.time == selectedTime ? "At Cursor" : "Nearest Entries")
                    }
                }
                if !entries.isEmpty {
                    DisclosureGroup("Recorded Entries", isExpanded: $showsRecordedEntries) {
                        ForEach(entries) { entry in
                            Button {
                                selection = entry.time
                                showsRecordedEntries = false
                                scroll.scrollTo("timeline-chart", anchor: .top)
                            } label: {
                                HStack {
                                    entry.label.foregroundStyle(.primary)
                                    if entry.time == selectedTime {
                                        Spacer()
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(entry.time == selectedTime ? .isSelected : [])
                        }
                    }
                }
                if showsLimitations, !experience.myIngestionsSorted.isEmpty {
                    Section("Models") {
                        NavigationLink {
                            RelativeExposureScreen(ingestions: experience.myIngestionsSorted)
                        } label: {
                            Label("Modeled Exposure", systemImage: "chart.xyaxis.line")
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            if model.totalWidth > 0 {
                Menu {
                    Picker("Timeline Zoom", selection: $zoom) {
                        Text("Fit to Screen").tag(1)
                        Text("2×").tag(2)
                        Text("4×").tag(4)
                    }
                    if model.supportsCombiningRoutes {
                        Toggle("Combine Comparable Routes", isOn: $combinesRoutes)
                    }
                } label: {
                    Label("Timeline Options", systemImage: "chart.xyaxis.line")
                }
            }
            if showsLimitations {
                NavigationLink(value: GlobalNavigationDestination.explainExperience) {
                    Label("Timeline Limitations", systemImage: "info.circle")
                }
            }
        }
        .sheet(item: $noteTime) { time in
            AddTimedNoteScreen(experience: experience, initialTime: time.time)
        }
        .sheet(item: $reminder) { JournalReminderEditor(draft: $0) }
    }

    private var cursorSection: some View {
        Group {
            Section {
                chart
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .id("timeline-chart")
                LabeledContent("Cursor Time") {
                    Text(selectedTime, format: TimelineCursorEntry.dateFormat).monospacedDigit()
                }
                if let estimate = model.effectEstimate(at: selectedTime) {
                    TimelineEstimateRows(estimate: estimate, time: selectedTime)
                }
            } header: {
                Text(model.groupDrawables.contains(where: \.hasDurationInfo) ? "Estimated Effects" : "Timeline")
            } footer: {
                if showsQuantityDetails, model.effectEstimate(at: selectedTime)?.curveScaledAmount(at: selectedTime) != nil {
                    Text("The curve-scaled amount is the logged amount multiplied by the curve’s relative height.")
                }
            }
            Section {
                Button {
                    noteTime = NoteTime(time: selectedTime)
                } label: {
                    Label("Add Note Here", systemImage: "note.text.badge.plus")
                }
                Menu {
                    if selectedTime > .now {
                        Button {
                            reminder = JournalReminderDraft(date: selectedTime, source: .timeline)
                        } label: {
                            Label("At Cursor Time", systemImage: "clock")
                        }
                    }
                    if let point = model.effectEstimate(at: .now)?.phase(at: .now) {
                        Button {
                            reminder = JournalReminderDraft(date: point.transition, source: .timeline)
                        } label: {
                            Label("At Estimated Phase End", systemImage: "waveform.path")
                        }
                    }
                    Button {
                        reminder = JournalReminderDraft()
                    } label: {
                        Label("Choose a Time", systemImage: "calendar")
                    }
                } label: {
                    Label("Set Reminder", systemImage: "bell")
                }
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: zoom > 1) {
                    let width = geometry.size.width * Double(zoom)
                    let fraction = selectedTime.timeIntervalSince(model.startTime) / max(1, model.totalWidth)
                    EffectTimeline(
                        timelineModel: model,
                        height: 220,
                        timeDisplayStyle: timeDisplayStyle,
                        cursorTime: selectedTime,
                        onTimeSelected: { selection = $0 },
                        allowsHorizontalScrub: zoom == 1
                    )
                    .frame(width: width)
                    .background {
                        GeometryReader { plot in
                            Color.clear.preference(
                                key: TimelinePlotPosition.self,
                                value: -plot.frame(in: .named(plotViewport)).minX / max(1, width)
                            )
                        }
                    }
                    .overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: max(0, min(width - 1, width * fraction)))
                            Color.clear
                                .frame(width: 1)
                                .id(zoomAnchor)
                        }
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: plotViewport)
                .onPreferenceChange(TimelinePlotPosition.self) { visibleStartFraction = $0 }
                .onChange(of: zoom) { _ in scroll.scrollTo(zoomAnchor, anchor: .center) }
                .onChange(of: selectedTime) { _ in
                    if zoom > 1 { scroll.scrollTo(zoomAnchor, anchor: .center) }
                }
            }
        }
        .frame(height: 220)
    }

    private struct NoteTime: Identifiable {
        let time: Date
        var id: Date { time }
    }
}

struct TimelineEstimateRows: View {
    let estimate: TimelineEffectEstimate
    let time: Date
    var showsCountdown = false
    @AppStorage(TimelineModel.showsQuantityDetailsKey) private var showsQuantityDetails = true

    var body: some View {
        if let status = estimate.phase(at: time) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(status.phase.rawValue)
                    if showsCountdown {
                        Text("\(Text(timerInterval: time...status.transition, countsDown: true)) left in phase")
                            .monospacedDigit()
                            .font(.caption)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Estimated Phase")
                    Text("\(estimate.substance) · \(estimate.route.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if !showsCountdown, showsQuantityDetails, let fraction = estimate.fractionOfPeak(at: time) {
            LabeledContent("Percent of Modeled Peak", value: fraction.formatted(.percent.precision(.fractionLength(0))))
            if let amount = estimate.curveScaledAmount(at: time), let unit = estimate.amountUnit {
                LabeledContent("Curve-scaled Amount", value: "\(amount.formatted(.number.precision(.significantDigits(1...2)))) \(unit)")
            }
        }
    }
}

private struct TimelinePlotPosition: PreferenceKey {
    static var defaultValue = 0.0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

struct TimelineCursorEntry: Identifiable {
    static let dateFormat = Date.FormatStyle().month(.abbreviated).day().hour().minute()

    let id: ObjectIdentifier
    let time: Date
    let title: String
    let icon: String

    var label: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                Text(time, format: Self.dateFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).accessibilityHidden(true)
        }
    }
}

#Preview {
    NavigationStack {
        TimelineScreen(
            timelineModel: TimelineModel(
                substanceGroups: EffectTimeline_Previews.substanceGroups,
                everythingForEachRating: EffectTimeline_Previews.everythingForEachRating,
                everythingForEachTimedNote: EffectTimeline_Previews.everythingForEachTimedNote,
                areRedosesDrawnIndividually: false,
                areSubstanceHeightsIndependent: false
            ),
            timeDisplayStyle: .regular)
    }
}
