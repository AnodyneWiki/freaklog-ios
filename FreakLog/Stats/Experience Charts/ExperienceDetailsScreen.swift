import Charts
import CoreData
import SwiftUI

struct ExperienceDetailsScreen: View {
  let experienceData: ExperienceData
  let ingestionData: ExperienceData
  @State private var timeRange: TimeRange = .last12Months
  @State private var showIngestions: Bool
  @State private var isShowingAverageLine: Bool = false
  @State private var highlightedSubstanceNames: [String] = []

  init(experienceData: ExperienceData, ingestionData: ExperienceData, showIngestions: Bool = false) {
    self.experienceData = experienceData
    self.ingestionData = ingestionData
    _showIngestions = State(initialValue: showIngestions)
  }

  private var activeData: ExperienceData {
    showIngestions ? ingestionData : experienceData
  }

  private var unitLabel: String {
    showIngestions ? "Ingestions" : "Experiences"
  }

  var body: some View {
    List {
      VStack(alignment: .leading) {
        Picker("", selection: $showIngestions) {
          Text("Experiences").tag(false)
          Text("Ingestions").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 4)
        TimeRangePicker(value: $timeRange)
          .padding(.bottom)
        ExperienceChart(
          experienceData: activeData,
          timeRange: timeRange,
          isShowingAverageLine: isShowingAverageLine && timeRange != .last30Days,
          colorMapping: getColor,
          unitLabel: unitLabel
        )
        .id(timeRange)
      }
      .listRowSeparator(.hidden)
      .chartLegend(.hidden)
      if timeRange != .last30Days {
        Section("Options") {
          Toggle(timeRange == .years ? "Show Yearly Average" : "Show Monthly Average", isOn: $isShowingAverageLine)
            .tint(.accentColor)
        }
      }
      Section {
        NavigationLink("View Entries") {
          StatsEntriesScreen(timeRange: timeRange, showsIngestions: showIngestions)
        }
      }
      let substanceCounts = activeData.getSubstanceExperienceCounts(in: timeRange)
      if !substanceCounts.isEmpty {
        Section(footer: showIngestions ? nil : Text("If a substance is one of n substances in an experience it is counted as 1/n experiences")) {
          ForEach(substanceCounts) { count in
            HStack {
              Image(systemName: "circle.fill")
                .foregroundColor(count.color)
              Text(count.substanceName)
                .font(.headline)
              Spacer()
              Text("\(count.experienceCount.asRoundedReadableString) \(unitLabel.lowercased())")
                .font(.subheadline)
                .foregroundColor(.secondary)
              if highlightedSubstanceNames.contains(count.substanceName) {
                Button {
                  withAnimation {
                    highlightedSubstanceNames.removeAll { name in
                      name == count.substanceName
                    }
                  }
                } label: {
                  Label("Remove Highlight", systemImage: "checkmark.circle").labelStyle(.iconOnly)
                }
              } else {
                Button {
                  withAnimation {
                    highlightedSubstanceNames.append(count.substanceName)
                  }
                } label: {
                  Label("Highlight", systemImage: "circle").labelStyle(.iconOnly)
                }
              }
            }
          }
        }
      }
      if !highlightedSubstanceNames.isEmpty {
        Section {
          Button("Clear Highlighted Substances") {
            highlightedSubstanceNames = []
          }
        }
      }
    }
    .navigationTitle(unitLabel)
  }

  private func getColor(name: String) -> Color {
    if highlightedSubstanceNames.isEmpty || highlightedSubstanceNames.contains(name) {
      return activeData.color(for: name)
    } else {
      return Color.gray.opacity(0.3)
    }
  }
}

struct StatsEntriesScreen: View {
  let timeRange: TimeRange
  var showsIngestions = false

  @FetchRequest(fetchRequest: PersistenceController.personalIngestionsRequest())
  private var ingestions: FetchedResults<Ingestion>
  @FetchRequest(fetchRequest: PersistenceController.experiencesRequest(prefetchingIngestions: true))
  private var experiences: FetchedResults<Experience>

  var body: some View {
    let now = Date.now
    List {
      if showsIngestions {
        let entries = ingestions.filter {
          timeRange.includes($0.timeUnwrapped, relativeTo: now)
        }
        if entries.isEmpty {
          Text("No ingestions in this period").foregroundStyle(.secondary)
        }
        ForEach(entries) { ingestion in
          JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.month().day().year().hour().minute())
        }
      } else {
        let entries = experiences.filter { experience in
          timeRange.includes(experience.sortDateUnwrapped, relativeTo: now)
            && !experience.myIngestionsSorted.isEmpty
        }
        if entries.isEmpty {
          Text("No experiences in this period").foregroundStyle(.secondary)
        }
        ForEach(entries) { experience in
          ExperienceRow(experience: experience, timeDisplayStyle: .regular)
        }
      }
    }
    .navigationTitle(showsIngestions ? "Ingestions" : "Experiences")
  }
}

#Preview {
  NavigationStack {
    ExperienceDetailsScreen(experienceData: .mock1, ingestionData: .mock1)
  }
}
