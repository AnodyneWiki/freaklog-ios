import Foundation

enum GlobalNavigationDestination: Hashable {
    // substance tab mainly
    case substance(substance: Substance)
    case editCustomSubstance(customSubstance: CustomSubstance)
    case webView(articleURL: URL)
    case webViewInteractions(substanceName: String, articleURL: URL)
    case timelineInfo

    // journal tab mainly
    case calendar
    case experience(experience: Experience)
    case chooseExperience(experiences: [Experience])
    case saferHallucinogen
    case allInteractions(substancesToCheck: [Substance])
    case toleranceTexts(substances: [SubstanceWithToleranceAndColor])
    case timeline(timelineModel: TimelineModel, timeDisplayStyle: TimeDisplayStyle)
    case explainExperience
    case dose(substance: Substance)

    // stats tab mainly
    case toleranceChart
    case toleranceChartExplanation
    case experienceDetails(experienceData: ExperienceData)
    case substanceDetails(substanceData: SubstanceData)
    case dosageStat(substanceName: String)

    // safer tab
    case saferRoutes
    case sprayCalculator
    case testingServices
    case reagentTesting
    case doseGuide
    case doseClassification
    case volumetricDosing
    case administrationRouteInfo

    // settings tab
    case editColors
    case customUnits
    case faq
    case customUnitsArchive
    case tabSettings
}
