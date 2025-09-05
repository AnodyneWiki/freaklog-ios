import Charts
import SwiftUI

struct ExperienceDetailsScreen: View {
    let experienceData: ExperienceData
    @State private var timeRange: TimeRange = .last12Months
    @State private var isShowingMonthlyAverageLine: Bool = false
    @State private var isShowingYearlyAverageLine: Bool = false
    @State private var highlightedSubstanceNames: [String] = []

    var body: some View {
        List {
            VStack(alignment: .leading) {
                TimeRangePicker(value: $timeRange)
                    .padding(.bottom)
                let chartHeight: CGFloat = 240
                switch timeRange {
                case .last30Days:
                    DailyExperienceChart(
                        experienceData: experienceData,
                        colorMapping: getColor,
                        chartHeight: chartHeight
                    )
                case .last12Months:
                    MonthlyExperienceChart(
                        experienceData: experienceData,
                        isShowingMonthlyAverageLine: isShowingMonthlyAverageLine,
                        colorMapping: getColor,
                        chartHeight: chartHeight
                    )
                case .years:
                    YearlyExperienceChart(
                        experienceData: experienceData,
                        isShowingYearlyAverageLine: isShowingYearlyAverageLine,
                        colorMapping: getColor,
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
            let substanceExperienceCounts = experienceData.getSubstanceExperienceCounts(in: timeRange)
            if !substanceExperienceCounts.isEmpty {
                Section(footer: Text("If a substance is one of n substances in an experience it is counted as 1/n experiences")) {
                    ForEach(substanceExperienceCounts) { count in
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(count.color)
                            Text(count.substanceName)
                                .font(.headline)
                            Spacer()
                            Text("\(count.experienceCount.asRoundedReadableString) experiences")
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
        .navigationTitle("Total Experiences")
    }

    private func getColor(name: String) -> Color {
        if highlightedSubstanceNames.isEmpty {
            return experienceData.colorMapping(name)
        }
        if highlightedSubstanceNames.contains(name) {
            return experienceData.colorMapping(name)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

#Preview {
    NavigationStack {
        ExperienceDetailsScreen(experienceData: .mock1)
    }
}
