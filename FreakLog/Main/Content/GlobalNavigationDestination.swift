import Foundation

enum GlobalNavigationDestination: Hashable {
    // substance tab mainly
    case substance(substance: Substance)
    case customSubstance(customSubstance: CustomSubstance)
    case substanceHistory(name: String)
    case editCustomSubstance(customSubstance: CustomSubstance)
    case webView(articleURL: URL)
    case webViewInteractions(substanceName: String, articleURL: URL)
    case timelineInfo
    case anodyneSubstance(title: String)
    case anodyneSearch(query: String)
    case anodyneUserNotes(notes: [AnodyneUserNote])
    case anodyneUserNote(note: AnodyneUserNote)
    case anodyneLinks(title: String, links: [AnodyneSubstance.Link])

    // journal tab mainly
    case unifiedSearch
    case calendar
    case experience(experience: Experience)
    case dynamicExperience(ingestions: [Ingestion])
    case chooseExperience(experiences: [Experience])
    case saferHallucinogen
    case allInteractions(substancesToCheck: [Substance], detected: [Interaction] = [])
    case interactionPair(Interaction)
    case toleranceTexts(substances: [SubstanceWithToleranceAndColor])
    case timeline(timelineModel: TimelineModel, timeDisplayStyle: TimeDisplayStyle)
    case explainExperience
    case dose(substance: Substance)

    // stats tab mainly
    case toleranceChart
    case toleranceChartExplanation
    case experienceDetails(experienceData: ExperienceData, ingestionData: ExperienceData, showIngestions: Bool)
    case substanceDetails(substanceData: SubstanceData)
    case dosageStat(substanceName: String)

    // tools tab
    case tools
    case dueToday
    case sprayCalculator
    case saferUse

    // safer use
    case saferRoutes
    case testingServices
    case reagentTesting
    case doseGuide
    case doseClassification
    case volumetricDosing
    case administrationRouteInfo

    // leaderboard
    case leaderboardServers
    case serverLeaderboard(serverID: UUID)

    // settings tab
    case editColors
    case customUnits
    case formulations
    case faq
    case customUnitsArchive
    case tabSettings
    case appIconSettings
    case webhookSettings
    case webhookArchive
    case journalSettings
    case anodyneSettings
    case assistantSettings
    // An existing provider, or a new one for nil
    case assistantProvider(id: UUID?)
}
