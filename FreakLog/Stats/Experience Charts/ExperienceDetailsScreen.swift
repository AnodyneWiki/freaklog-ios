import Charts
import SwiftUI

struct ExperienceDetailsScreen: View {
  let experienceData: ExperienceData
  let ingestionData: ExperienceData
  @State private var timeRange: TimeRange = .last12Months
  @State private var showIngestions = false
  @State private var isShowingMonthlyAverageLine: Bool = false
  @State private var isShowingYearlyAverageLine: Bool = false
  @State private var highlightedSubstanceNames: [String] = []

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
        let chartHeight: CGFloat = 240
        switch timeRange {
        case .last30Days:
          DailyExperienceChart(
            experienceData: activeData,
            colorMapping: getColor,
            unitLabel: unitLabel,
            chartHeight: chartHeight
          )
        case .last12Months:
          MonthlyExperienceChart(
            experienceData: activeData,
            isShowingMonthlyAverageLine: isShowingMonthlyAverageLine,
            colorMapping: getColor,
            unitLabel: unitLabel,
            chartHeight: chartHeight
          )
        case .years:
          YearlyExperienceChart(
            experienceData: activeData,
            isShowingYearlyAverageLine: isShowingYearlyAverageLine,
            colorMapping: getColor,
            unitLabel: unitLabel,
            chartHeight: chartHeight
          )
        }
      }
      .listRowSeparator(.hidden)
      .chartLegend(.hidden)
      if timeRange == .last12Months {
        Section("Options") {
          Toggle("Show Monthly Average", isOn: $isShowingMonthlyAverageLine).tint(.accentColor)
        }
      } else if timeRange == .years {
        Section("Options") {
          Toggle("Show Yearly Average", isOn: $isShowingYearlyAverageLine).tint(.accentColor)
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
    .navigationTitle("Statistics")
  }

  private func getColor(name: String) -> Color {
    if highlightedSubstanceNames.isEmpty {
      return activeData.colorMapping(name)
    }
    if highlightedSubstanceNames.contains(name) {
      return activeData.colorMapping(name)
    } else {
      return Color.gray.opacity(0.3)
    }
  }
}

#Preview {
  NavigationStack {
    ExperienceDetailsScreen(experienceData: .mock1, ingestionData: .mock1)
  }
}
