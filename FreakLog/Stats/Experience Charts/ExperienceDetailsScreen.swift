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

  @State private var substance: String? = nil
  @State private var route: AdministrationRoute? = nil
  @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen = false

  @FetchRequest(fetchRequest: PersistenceController.personalIngestionsRequest())
  private var ingestions: FetchedResults<Ingestion>
  @FetchRequest(fetchRequest: PersistenceController.experiencesRequest(prefetchingIngestions: true))
  private var experiences: FetchedResults<Experience>

  private var hasFilters: Bool { substance != nil || (isEyeOpen && route != nil) }

  private var periodTitle: LocalizedStringKey {
    switch timeRange {
    case .last30Days: "Last 30 Days"
    case .last12Months: "Last 12 Months"
    case .years: "All Time"
    }
  }

  var body: some View {
    let now = Date.now
    List {
      if showsIngestions {
        let periodEntries = ingestions.filter {
          timeRange.includes($0.timeUnwrapped, relativeTo: now)
        }
        filters(for: periodEntries)
        let entries = periodEntries.filter(matchesFilters)
        Section(periodTitle) {
          if entries.isEmpty {
            Text(hasFilters ? "No ingestions match these filters" : "No ingestions in this period")
              .foregroundStyle(.secondary)
          }
          ForEach(entries) { ingestion in
            JournalEntryLink(ingestion: ingestion, timeFormat: .dateTime.month().day().year().hour().minute())
          }
        }
      } else {
        let periodEntries = experiences
          .filter { timeRange.includes($0.sortDateUnwrapped, relativeTo: now) }
          .map { (experience: $0, ingestions: $0.myIngestionsSorted) }
          .filter { !$0.ingestions.isEmpty }
        filters(for: periodEntries.flatMap(\.ingestions))
        let entries = periodEntries.filter { $0.ingestions.contains(where: matchesFilters) }.map(\.experience)
        Section(periodTitle) {
          if entries.isEmpty {
            Text(hasFilters ? "No experiences match these filters" : "No experiences in this period")
              .foregroundStyle(.secondary)
          }
          ForEach(entries) { experience in
            ExperienceRow(experience: experience, timeDisplayStyle: .regular)
          }
        }
      }
    }
    .navigationTitle(showsIngestions ? "Ingestions" : "Experiences")
    .onChange(of: isEyeOpen) { isOpen in
      if !isOpen { route = nil }
    }
  }

  @ViewBuilder
  private func filters(for entries: [Ingestion]) -> some View {
    if !entries.isEmpty || hasFilters {
      let storedNames = Set(entries.map(\.substanceNameUnwrapped) + [substance].compactMap { $0 })
      let displayNames = storedNames.map { name in
        (stored: name, display: PersistenceController.shared.displayName(for: name))
      }
      let namesByLabel = Dictionary(grouping: displayNames, by: { $0.display.lowercased() })
      let options = displayNames.map { name in
        let isAmbiguous = namesByLabel[name.display.lowercased(), default: []].count > 1
        return (stored: name.stored, label: isAmbiguous && name.stored != name.display
          ? "\(name.display) (\(name.stored))" : name.display)
      }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
      Section {
        Picker("Substance", selection: $substance) {
          Text("All Substances").tag(nil as String?)
          ForEach(options, id: \.stored) { option in
            Text(option.label).tag(Optional(option.stored))
          }
        }
        if isEyeOpen {
          let availableRoutes = Set(entries.map(\.administrationRouteUnwrapped) + [route].compactMap { $0 })
          Picker("Route", selection: $route) {
            Text("All Routes").tag(nil as AdministrationRoute?)
            ForEach(AdministrationRoute.allCases.filter { availableRoutes.contains($0) }) { option in
              Text(option.rawValue.localizedCapitalized).tag(Optional(option))
            }
          }
        }
        if hasFilters {
          Button("Reset Filters") {
            substance = nil
            route = nil
          }
        }
      } header: {
        Text("Filters")
      } footer: {
        if !showsIngestions {
          Text("Filters match your own ingestions in each experience.")
        }
      }
    }
  }

  private func matchesFilters(_ ingestion: Ingestion) -> Bool {
    (substance == nil || substance == ingestion.substanceNameUnwrapped)
      && (!isEyeOpen || route == nil || route == ingestion.administrationRouteUnwrapped)
  }
}

#Preview {
  NavigationStack {
    ExperienceDetailsScreen(experienceData: .mock1, ingestionData: .mock1)
  }
}
