import CoreData

@MainActor
final class MigrationManager {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func migrateCompanionsAndExperienceSortDates() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            var companionsDict: [String: SubstanceCompanion] = [:]
            for ingestion in allIngestions {
                guard let name = ingestion.substanceName else { continue }
                guard let colorUnwrap = ingestion.color else { continue }
                if let companion = companionsDict[name] {
                    ingestion.substanceCompanion = companion
                } else {
                    let companion = SubstanceCompanion(context: viewContext)
                    companion.substanceName = name
                    companion.colorAsText = colorUnwrap
                    ingestion.substanceCompanion = companion
                    companionsDict[name] = companion
                }
            }
            let experienceFetchRequest = Experience.fetchRequest()
            let allExperiences = (try? viewContext.fetch(experienceFetchRequest)) ?? []
            for experience in allExperiences {
                experience.sortDate = experience.ingestionsSorted.first?.time ?? experience.creationDate
            }
            try? viewContext.save()
        }
    }

    func migrateIngestionNamesAndUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Psilocybin Mushrooms" {
                    ingestion.substanceName = "Psilocybin mushrooms"
                }
                if ingestion.units == "mg (THC)" {
                    ingestion.units = "mg"
                }
                if ingestion.units == "70" {
                    ingestion.units = "mg"
                }
            }
            try? viewContext.save()
        }
    }

    func migrateBenzydamineUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Benzydamine" && ingestion.units == "g" {
                    ingestion.units = "mg"
                    ingestion.dose = ingestion.dose * 1000
                }
            }
            try? viewContext.save()
        }
    }

    func migrateCannabisAndMushroomUnits() {
        viewContext.performAndWait {
            let ingestionFetchRequest = Ingestion.fetchRequest()
            let allIngestions = (try? viewContext.fetch(ingestionFetchRequest)) ?? []
            for ingestion in allIngestions {
                if ingestion.substanceName == "Cannabis" && ingestion.units == "mg" {
                    ingestion.units = "mg THC"
                }
                if ingestion.substanceName == "Psilocybin mushrooms" && ingestion.units == "mg" {
                    ingestion.units = "mg Psilocybin"
                }
            }

            let customUnitFetchRequest = CustomUnit.fetchRequest()
            let customUnits = (try? viewContext.fetch(customUnitFetchRequest)) ?? []
            for customUnit in customUnits {
                if customUnit.substanceName == "Cannabis" && customUnit.originalUnit == "mg" {
                    customUnit.originalUnit = "mg THC"
                }
                if customUnit.substanceName == "Psilocybin mushrooms" && customUnit.originalUnit == "mg" {
                    customUnit.originalUnit = "mg Psilocybin"
                }
            }

            try? viewContext.save()
        }
    }

    func migrateColors() {
        viewContext.performAndWait {
            let companionFetchRequest = SubstanceCompanion.fetchRequest()
            let allCompanions = (try? viewContext.fetch(companionFetchRequest)) ?? []
            for companion in allCompanions {
                companion.colorAsText = companion.colorAsText?.uppercased()
            }
            let timedNotesFetchRequest = TimedNote.fetchRequest()
            let allTimedNotes = (try? viewContext.fetch(timedNotesFetchRequest)) ?? []
            for timedNote in allTimedNotes {
                timedNote.colorAsText = timedNote.colorAsText?.uppercased()
            }
            try? viewContext.save()
        }
    }
}
