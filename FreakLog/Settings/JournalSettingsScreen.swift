import SwiftUI

struct JournalSettingsScreen: View {
    @AppStorage(PersistenceController.defaultJournalViewKey) var defaultJournalView: JournalViewOption = .allIngestions
    @AppStorage(PersistenceController.dynamicExperienceRangeHoursKey) var dynamicRange: DynamicRangeOption = .twentyFourHours
    @AppStorage(PersistenceController.isHidingJournalTabSwitcherKey) var isHidingJournalTabSwitcher: Bool = false
    @AppStorage(PersistenceController.fabButtonPositionKey) var fabButtonPosition: FabButtonPosition = .right
    @AppStorage(PersistenceController.areRedosesDrawnIndividuallyKey) var areRedosesDrawnIndividually: Bool = true
    @AppStorage(PersistenceController.independentSubstanceHeightKey) var areSubstanceHeightsIndependent: Bool = true
    @AppStorage(TimelineModel.combinesComparableRoutesKey) private var combinesRoutes = false
    @AppStorage(TimelineModel.showsQuantityDetailsKey) private var showsQuantityDetails = true
    @AppStorage(PersistenceController.isHidingDosageDotsKey) var isHidingDosageDots: Bool = false
    @AppStorage(PersistenceController.isHidingToleranceChartInExperienceKey) var isHidingToleranceChartInExperience: Bool = false
    @AppStorage(PersistenceController.isHidingSubstanceInfoInExperienceKey) var isHidingSubstanceInfoInExperience: Bool = false
    @AppStorage(PersistenceController.shouldAutomaticallyStartLiveActivityKey) var shouldAutomaticallyStartLiveActivity = true
    @AppStorage(AdministrationSiteNameStyle.preferenceKey) private var siteNameStyle = AdministrationSiteNameStyle.simple

    @AppStorage(PersistenceController.confirmsIngestionDeletionKey) private var confirmsIngestionDeletion = true

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

                Picker("Site Names", selection: $siteNameStyle) {
                    ForEach(AdministrationSiteNameStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            Section {
                Toggle("Confirm Ingestion Deletion", isOn: $confirmsIngestionDeletion)
                    .tint(.accentColor)
            } header: {
                Text("Editing")
            } footer: {
                Text("Entries linked to inventory and batches of unconfirmed entries always ask for confirmation.")
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
                Toggle("Combine comparable routes", isOn: $combinesRoutes)
                Toggle("Timeline quantity details", isOn: $showsQuantityDetails)
                Toggle("Dosage dots", isOn: $isHidingDosageDots.inverted)
            } header: {
                Text("Timeline")
            } footer: {
                Text("Combine routes when they share a reference amount and have complete duration estimates. Independent heights scale curves to fit separately.")
            }
            .tint(.accentColor)

            Section("Experience") {
                Toggle("Tolerance chart", isOn: $isHidingToleranceChartInExperience.inverted)
                Toggle("Substance info", isOn: $isHidingSubstanceInfoInExperience.inverted)
                if LiveActivities.areAvailable {
                    Toggle("Automatic live activities", isOn: $shouldAutomaticallyStartLiveActivity)
                }
            }
            .tint(.accentColor)

            Section {
                NavigationLink {
                    JournalRemindersScreen()
                } label: {
                    Label("Journal Reminders", systemImage: "bell")
                }
                NavigationLink(value: GlobalNavigationDestination.editColors) {
                    Label("Substance Colors & Visibility", systemImage: "paintpalette")
                }
            }
        }
        .navigationTitle("Journal & Timeline")
    }
}

#Preview {
    NavigationStack {
        JournalSettingsScreen()
    }
}
