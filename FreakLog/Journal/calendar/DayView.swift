import SwiftUI
import HorizonCalendar

struct DayView: View {

    private let dayComponents: DayComponents
    @FetchRequest var ingestions : FetchedResults<Ingestion>
    let isToday: Bool

    init(dayComponents: DayComponents) {
        self.dayComponents = dayComponents
        let startOfDay = Calendar.current.date(from: dayComponents.components) ?? .now
        self._ingestions = FetchRequest(fetchRequest: PersistenceController.ingestionsRequest(for: startOfDay))
        isToday = startOfDay == Calendar.current.startOfDay(for: .now)
    }

    private let colorHeight: Double = 6

    var body: some View {
        let experiences = experiences
        if let firstExperience = experiences.first {
            NavigationLink(
                value: experiences.count > 1
                    ? GlobalNavigationDestination.chooseExperience(experiences: experiences)
                    : .experience(experience: firstExperience)
            ) {
                experienceDayLabel
            }
        } else {
            VStack(spacing: 0) {
                textWithColor
                Color.clear.frame(height: colorHeight)
            }
        }
    }

    private var textWithColor: Text {
        if isToday {
            text.foregroundColor(.accentColor)
        } else if ingestions.isEmpty {
            text.foregroundColor(.secondary)
        } else {
            text.foregroundColor(.primary)
        }
    }

    private var text: Text {
        Text("\(dayComponents.day)")
    }

    private var experienceDayLabel: some View {
        VStack(spacing: 0) {
            textWithColor
            CalendarColorRectangle(colors: ingestions.map({$0.substanceColor.swiftUIColor}))
                .frame(height: colorHeight).padding(.horizontal, 5)
        }
    }

    private var experiences: [Experience] {
        ingestions.compactMap {$0.experience}.uniqued().sorted { lhs, rhs in
            lhs.sortDateUnwrapped < rhs.sortDateUnwrapped
        }
    }
}
