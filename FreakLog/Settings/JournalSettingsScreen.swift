import SwiftUI

struct JournalSettingsScreen: View {
    @AppStorage(PersistenceController.defaultJournalViewKey) var defaultJournalView: JournalViewOption = .allIngestions
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) var dynamicRange: DynamicRangeOption = .twentyFourHours
    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPosition: FabButtonPosition = .center
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true

    var body: some View {
        List {
            Section("Journal") {
                Picker(selection: $defaultJournalView) {
                    ForEach(JournalViewOption.allCases) { option in
                        Text(option.text).tag(option)
                    }
                } label: {
                    Label("Default Tab", systemImage: "list.dash.header.rectangle")
                }

                Picker(selection: $fabButtonPosition) {
                    ForEach(FabButtonPosition.allCases) { position in
                        Text(position.text).tag(position)
                    }
                } label: {
                    Label("Button Position", systemImage: "arrow.left.and.right.square")
                }

                Toggle("Tab Switcher", isOn: $isHidingJournalTabSwitcher.inverted)
                    .tint(.accentColor)
            }

            Section("Ingestion Overview") {
                Picker(selection: $dynamicRange) {
                    ForEach(DynamicRangeOption.allCases) { option in
                        Text(option.text).tag(option)
                    }
                } label: {
                    Label("Time Range", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                Toggle("Draw redoses individually", isOn: $areRedosesDrawnIndividually)
                Toggle("Independent substance heights", isOn: $areSubstanceHeightsIndependent)
            } header: {
                Text("Timeline")
            } footer: {
                Text(
                    "Redoses drawn individually get their own curve instead of adding up into one. "
                        + "Independent heights scale each substance to its own maximum "
                        + "instead of comparing heights across substances."
                )
            }
            .tint(.accentColor)
        }
        .navigationTitle("Journal Settings")
    }
}

#Preview {
    NavigationStack {
        JournalSettingsScreen()
    }
}
