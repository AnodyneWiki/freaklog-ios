import SwiftUI

struct JournalSettingsScreen: View {
    @AppStorage(PersistenceController.defaultJournalViewKey) var defaultJournalView: Int = JournalViewOption.allIngestions.rawValue
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) var dynamicExperienceRangeHours: Int = 24
    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPositionString: String = FabButtonPosition.center.rawValue

    var fabButtonPosition: FabButtonPosition {
        FabButtonPosition(rawValue: fabButtonPositionString) ?? .center
    }

    var body: some View {
        let journalViewBinding = Binding {
            JournalViewOption(rawValue: defaultJournalView) ?? .experiences
        } set: { newValue in
            defaultJournalView = newValue.rawValue
        }

        let dynamicRangeBinding = Binding {
            DynamicRangeOption(rawValue: dynamicExperienceRangeHours) ?? .twentyFourHours
        } set: { newValue in
            dynamicExperienceRangeHours = newValue.rawValue
        }

        let fabPositionBinding = Binding {
            fabButtonPosition
        } set: { newValue in
            fabButtonPositionString = newValue.rawValue
        }

        List {
            Section("Journal") {
                Picker(selection: journalViewBinding) {
                    ForEach(JournalViewOption.allCases) { option in
                        Text(option.text).tag(option)
                    }
                } label: {
                    Label("Default Tab", systemImage: "list.dash.header.rectangle")
                }
                
                Picker(selection: fabPositionBinding) {
                    ForEach(FabButtonPosition.allCases) { position in
                        Text(position.text).tag(position)
                    }
                } label: {
                    Label("Button Position", systemImage: "arrow.left.and.right.square")
                }
                
                Toggle("Hide Tab Switcher", isOn: $isHidingJournalTabSwitcher)
                    .tint(.accentColor)
            }
            
            Section("Ingestion Overview") {
                Picker(selection: dynamicRangeBinding) {
                    ForEach(DynamicRangeOption.allCases) { option in
                        Text(option.text).tag(option)
                    }
                } label: {
                    Label("Time Range", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("Journal Settings")
    }
}

#Preview {
    NavigationStack {
        JournalSettingsScreen()
    }
}
