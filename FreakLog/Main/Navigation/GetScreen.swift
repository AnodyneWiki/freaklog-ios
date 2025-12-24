import SwiftUI

@MainActor
func getScreen(from destination: GlobalNavigationDestination) -> some View {
    Group {
        switch destination {
        case let .editCustomSubstance(customSubstance):
            EditCustomSubstanceView(customSubstance: customSubstance)
        case let .substance(substance):
            SubstanceScreen(substance: substance)
        case let .webView(articleURL):
            WebViewScreen(articleURL: articleURL)
        case let .webViewInteractions(substanceName, interactionURL):
            WebViewScreen(articleURL: interactionURL)
                .navigationTitle("\(substanceName) Interactions")
        case let .dose(substance):
            List {
                DosesSection(substance: substance)
            }.navigationTitle("\(substance.name) Dosage")
        case .timelineInfo:
            List {
                TimelineExplanationTexts()
            }.navigationTitle("Timeline Info")
        case .calendar:
            JournalCalendarScreen()
        case let .experience(experience):
            ExperienceScreen(experience: experience)
        case let .dynamicExperience(ingestions):
            DynamicExperienceScreen(ingestions: ingestions)
        case let .chooseExperience(experiences):
            List(experiences) { experience in
                ExperienceRow(experience: experience, timeDisplayStyle: .regular)
            }
        case .saferHallucinogen:
            SaferHallucinogenScreen()
        case let .allInteractions(substancesToCheck):
            GoThroughAllInteractionsScreen(substancesToCheck: substancesToCheck)
        case let .toleranceTexts(substances):
            ToleranceTextsScreen(substances: substances)
        case .toleranceChartExplanation:
            ToleranceChartExplanationScreen()
        case .toleranceChart:
            ToleranceChartScreen()
        case let .experienceDetails(experienceData):
            ExperienceDetailsScreen(experienceData: experienceData)
        case let .substanceDetails(substanceData):
            SubstanceDetailsScreen(substanceData: substanceData)
        case .saferRoutes:
            SaferRoutesScreen()
        case .sprayCalculator:
            SprayCalculatorScreen()
        case .testingServices:
            TestingServicesScreen()
        case .reagentTesting:
            ReagentTestingScreen()
        case .doseGuide:
            DosageGuideScreen()
        case .doseClassification:
            DosageClassificationScreen()
        case .volumetricDosing:
            VolumetricDosingScreen()
        case .administrationRouteInfo:
            AdministrationRouteScreen()
        case .editColors:
            EditColorsScreen()
        case .customUnits:
            CustomUnitsScreen()
        case .webhookSettings:
            WebhooksScreen()
        case .webhookArchive:
            WebhookArchiveScreen()
        case .faq:
            FAQView()
        case .customUnitsArchive:
            CustomUnitsArchiveScreen()
        case .tabSettings:
            TabSettingsScreen()
        case .journalSettings:
            JournalSettingsScreen()
        case let .timeline(timelineModel, timeDisplayStyle):
            TimelineScreen(timelineModel: timelineModel, timeDisplayStyle: timeDisplayStyle)
        case .explainExperience:
            ExplainExperienceSectionScreen()
        case let .dosageStat(substanceName):
            DosageStatScreen(substanceName: substanceName)
        }
    }
}

