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

// The expanded view of a saved experience. Each selectable time comes from the
// journal even when the timeline has no estimate for the event.
struct ExperienceTimelineScreen: View {
    @ObservedObject var experience: Experience

    @AppStorage(PersistenceController.timeDisplayStyleKey) private var storedTimeStyle: SaveableTimeDisplayStyle = .auto
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) private var drawsRedosesIndividually = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) private var usesIndependentHeights = true
    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

    var body: some View {
        TimelineCursorContent(
            experience: experience,
            model: experience.getMyTimeLineModel(
                areRedosesDrawnIndividually: drawsRedosesIndividually,
                areSubstanceHeightsIndependent: usesIndependentHeights
            ),
            entries: recordedEntries,
            timeDisplayStyle: storedTimeStyle.resolved(isCurrent: experience.isCurrent),
            showsLimitations: isEyeOpen
        )
        .observeExperienceTimeline(experience)
    }

    private var recordedEntries: [TimelineCursorEntry] {
        let ingestions = experience.myIngestionsSorted.compactMap { ingestion -> TimelineCursorEntry? in
            guard let date = ingestion.time, !ingestion.isHiddenFromTimeline else { return nil }
            return TimelineCursorEntry(id: ingestion.id, time: date, title: ingestion.substanceDisplayName, icon: "pills")
        }
        let notes = experience.timedNotesSorted.compactMap { note -> TimelineCursorEntry? in
            guard let date = note.time else { return nil }
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

    @State private var selection: Date?
    @State private var noteTime: NoteTime?
    @State private var zoom = 1.0
    @State private var showsRecordedEntries = false

    private var selectedTime: Date { selection ?? entries.first?.time ?? model.startTime }

    var body: some View {
        ScrollViewReader { scroll in
            List {
                cursorSection
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
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            if showsLimitations {
                NavigationLink(value: GlobalNavigationDestination.explainExperience) {
                    Label("Timeline Limitations", systemImage: "info.circle")
                }
            }
        }
        .sheet(item: $noteTime) { time in
            AddTimedNoteScreen(experience: experience, initialTime: time.time)
        }
    }

    private var cursorSection: some View {
        Section {
            chart
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                .id("timeline-chart")
            LabeledContent("Cursor Time") {
                Text(selectedTime, format: TimelineCursorEntry.dateFormat).monospacedDigit()
            }
            if model.totalWidth > 0 {
                Slider(value: elapsedTime, in: 0...model.totalWidth) {
                    Text("Timeline Position")
                }
                .accessibilityValue(Text(selectedTime, format: TimelineCursorEntry.dateFormat))
                Stepper(value: $zoom, in: 1...6) {
                    LabeledContent("Zoom", value: "\(Int(zoom))×")
                }
            }
            Button {
                noteTime = NoteTime(time: selectedTime)
            } label: {
                Label("Add Note Here", systemImage: "note.text.badge.plus")
            }
        } header: {
            Text(model.groupDrawables.contains(where: \.hasDurationInfo) ? "Estimated Effects" : "Timeline")
        }
    }

    private var elapsedTime: Binding<Double> {
        Binding {
            min(max(0, selectedTime.timeIntervalSince(model.startTime)), model.totalWidth)
        } set: { elapsed in
            selection = model.startTime.addingTimeInterval(elapsed)
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width
            let chartWidth = viewportWidth * zoom
            let x = selectedTime.timeIntervalSince(model.startTime) / max(1, model.totalWidth) * chartWidth
            let offset = min(max(0, x - viewportWidth / 2), chartWidth - viewportWidth)
            EffectTimeline(
                timelineModel: model,
                height: geometry.size.height,
                timeDisplayStyle: timeDisplayStyle,
                cursorTime: selectedTime,
                onTimeSelected: { selection = $0 }
            )
            .frame(width: chartWidth)
            .offset(x: -offset)
            .frame(width: viewportWidth, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .frame(height: 220)
    }

    private struct NoteTime: Identifiable {
        let time: Date
        var id: Date { time }
    }
}

private struct TimelineCursorEntry: Identifiable {
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
