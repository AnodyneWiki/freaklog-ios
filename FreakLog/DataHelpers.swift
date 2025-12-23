import CoreData

extension PersistenceController {
    func getIngestionsBetween(startDate: Date, endDate: Date) -> [Ingestion] {
        let fetchRequest = Ingestion.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(time >= %@) AND (time <= %@)", startDate as NSDate, endDate as NSDate)
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getLatestActiveExperience() -> Experience? {
        let fetchRequest = Experience.fetchRequest()
        let minusThreeDays: TimeInterval = -3*24*60*60
        let startDate = Date.now.addingTimeInterval(minusThreeDays)
        fetchRequest.predicate = NSPredicate(format: "sortDate >= %@", startDate as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        let experiences = (try? viewContext.fetch(fetchRequest)) ?? []
        return experiences.first { experience in
            experience.isCurrent
        }
    }

    func getLatestExperience() -> Experience? {
        let fetchRequest = Experience.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Experience.sortDate, ascending: false)]
        fetchRequest.fetchLimit = 1
        let experiences = (try? viewContext.fetch(fetchRequest)) ?? []
        return experiences.first
    }

    func getSubstanceCompanions() -> [SubstanceCompanion] {
        let fetchRequest = SubstanceCompanion.fetchRequest()
        return (try? viewContext.fetch(fetchRequest)) ?? []
    }

    func getCustomSubstance(name: String) -> CustomSubstance? {
        let fetchRequest = CustomSubstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        let results = try? viewContext.fetch(fetchRequest)
        return results?.first
    }
}
