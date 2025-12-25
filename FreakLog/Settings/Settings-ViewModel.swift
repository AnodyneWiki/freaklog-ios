import CoreData
import Foundation

extension SettingsScreen {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var isExporting = false
        @Published var journalFile = JournalFile(experiences: [], customSubstances: [], customUnits: [])
        @Published var isShowingToast = false
        @Published var isShowingSuccessToast = false
        @Published var toastMessage = ""

        func exportData() {
            let experienceFetchRequest = Experience.fetchRequest()
            let allExperiences = (try? PersistenceController.shared.viewContext.fetch(experienceFetchRequest)) ?? []
            let customFetchRequest = CustomSubstance.fetchRequest()
            let allCustomSubstances = (try? PersistenceController.shared.viewContext.fetch(customFetchRequest)) ?? []
            let customUnitsFetchRequest = CustomUnit.fetchRequest()
            let allCustomUnits = (try? PersistenceController.shared.viewContext.fetch(customUnitsFetchRequest)) ?? []
            journalFile = JournalFile(
                experiences: allExperiences,
                customSubstances: allCustomSubstances,
                customUnits: allCustomUnits)
            isExporting = true
        }

        // swiftlint:disable cyclomatic_complexity function_body_length
        func importData(data: Data) {
            Task {
                do {
                    let container = PersistenceController.shared.container
                    
                    // Decode off the main thread first
                    let data = tryConvertFile(data)
                    let file = try JSONDecoder().decode(JournalFile.self, from: data)
                    
                    await container.performBackgroundTask { context in
                        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                        
                        do {
                            // First delete everything in this background context
                            try PersistenceController.shared.deleteEverything(blockContext: context)
                            
                            // companions
                            var companionDict: [String: SubstanceCompanion] = [:]
                            for companionCodable in file.substanceCompanions {
                                let newCompanion = SubstanceCompanion(context: context)
                                newCompanion.substanceName = companionCodable.substanceName
                                newCompanion.colorAsText = companionCodable.color.rawValue
                                companionDict[companionCodable.substanceName] = newCompanion
                            }
                            // custom units
                            var unitsDict: [Int32: CustomUnit] = [:]
                            for customUnitCodable in file.customUnits {
                                let newUnit = CustomUnit(context: context)
                                newUnit.substanceName = customUnitCodable.substanceName
                                newUnit.name = customUnitCodable.name
                                newUnit.creationDate = customUnitCodable.creationDate
                                newUnit.administrationRoute = customUnitCodable.administrationRoute.rawValue
                                newUnit.dose = customUnitCodable.dose ?? 0
                                newUnit.estimatedDoseStandardDeviation = customUnitCodable.estimatedDoseStandardDeviation ?? 0
                                newUnit.isEstimate = customUnitCodable.isEstimate
                                newUnit.isArchived = customUnitCodable.isArchived
                                newUnit.unit = customUnitCodable.unit
                                newUnit.unitPlural = customUnitCodable.unitPlural
                                newUnit.originalUnit = customUnitCodable.originalUnit
                                newUnit.note = customUnitCodable.note
                                newUnit.idForAndroid = customUnitCodable.id
                                unitsDict[customUnitCodable.id] = newUnit
                            }
                            // experience
                            for experienceCodable in file.experiences {
                                let newExperience = Experience(context: context)
                                newExperience.title = experienceCodable.title
                                newExperience.text = experienceCodable.text
                                newExperience.creationDate = experienceCodable.creationDate
                                newExperience.sortDate = experienceCodable.sortDate
                                newExperience.isFavorite = experienceCodable.isFavorite
                                // ingestion
                                for ingestionCodable in experienceCodable.ingestions {
                                    let newIngestion = Ingestion(context: context)
                                    newIngestion.substanceName = ingestionCodable.substanceName
                                    newIngestion.time = ingestionCodable.time
                                    newIngestion.endTime = ingestionCodable.endTime
                                    newIngestion.creationDate = ingestionCodable.creationDate
                                    newIngestion.administrationRoute = ingestionCodable.administrationRoute.rawValue
                                    newIngestion.dose = ingestionCodable.dose ?? 0
                                    newIngestion.estimatedDoseStandardDeviation = ingestionCodable.estimatedDoseStandardDeviation ?? 0
                                    newIngestion.isEstimate = ingestionCodable.isDoseAnEstimate
                                    newIngestion.units = ingestionCodable.units
                                    newIngestion.note = ingestionCodable.notes
                                    newIngestion.consumerName = ingestionCodable.consumerName
                                    newIngestion.administrationSite = ingestionCodable.administrationSite
                                    if let ingestionLocation = ingestionCodable.location {
                                        let newLocation = ExperienceLocation(context: context)
                                        newLocation.name = ingestionLocation.name
                                        newLocation.latitude = ingestionLocation.latitude ?? 0
                                        newLocation.longitude = ingestionLocation.longitude ?? 0
                                        newIngestion.location = newLocation
                                    } else if let experienceLocation = experienceCodable.location {
                                        let newLocation = ExperienceLocation(context: context)
                                        newLocation.name = experienceLocation.name
                                        newLocation.latitude = experienceLocation.latitude ?? 0
                                        newLocation.longitude = experienceLocation.longitude ?? 0
                                        newIngestion.location = newLocation
                                    }
                                    newExperience.addToIngestions(newIngestion)
                                    // add companion to ingestion
                                    if let companion = companionDict[ingestionCodable.substanceName] {
                                        newIngestion.substanceCompanion = companion
                                    } else {
                                        // assertionFailure("Found no corresponding substance companion for ingestion")
                                        let newCompanion = SubstanceCompanion(context: context)
                                        newCompanion.substanceName = ingestionCodable.substanceName
                                        newCompanion.colorAsText = (SubstanceColor.allCases.randomElement() ?? .red).rawValue
                                        companionDict[ingestionCodable.substanceName] = newCompanion
                                        newIngestion.substanceCompanion = newCompanion
                                    }
                                    // add custom unit to ingestion
                                    if let customUnitId = ingestionCodable.customUnitId {
                                        newIngestion.customUnit = unitsDict[customUnitId]
                                    }
                                }
                                // ratings
                                for ratingCodable in experienceCodable.ratings {
                                    let newRating = ShulginRating(context: context)
                                    newRating.creationDate = ratingCodable.creationDate
                                    newRating.time = ratingCodable.time
                                    newRating.option = ratingCodable.option.rawValue
                                    newRating.experience = newExperience
                                }
                                // timed notes
                                for timedNoteCodable in experienceCodable.timedNotes {
                                    let newTimedNote = TimedNote(context: context)
                                    newTimedNote.creationDate = timedNoteCodable.creationDate
                                    newTimedNote.time = timedNoteCodable.time
                                    newTimedNote.note = timedNoteCodable.note
                                    newTimedNote.colorAsText = timedNoteCodable.color.rawValue
                                    newTimedNote.isPartOfTimeline = timedNoteCodable.isPartOfTimeline
                                    newTimedNote.experience = newExperience
                                }
                                // location
                                if let location = experienceCodable.location {
                                    let newLocation = ExperienceLocation(context: context)
                                    newLocation.name = location.name
                                    newLocation.latitude = location.latitude ?? 0
                                    newLocation.longitude = location.longitude ?? 0
                                    newExperience.legacyLocation = newLocation
                                }
                            }
                            for customCodable in file.customSubstances {
                                let newCustom = CustomSubstance(context: context)
                                newCustom.name = customCodable.name
                                newCustom.units = customCodable.units
                                newCustom.explanation = customCodable.description
                            }
                            
                            if context.hasChanges {
                                try context.save()
                            }

                            Task { @MainActor in
                                self.showSuccessToast(message: "Import Successful")
                            }
                        } catch {
                            print("Background import failed: \(error)")
                            Task { @MainActor in
                                self.showErrorToast(message: "Import Failed")
                            }
                        }
                    }
                } catch {
                    print("Decoding failed: \(error)")
                    await MainActor.run {
                        self.showErrorToast(message: "Import Failed")
                    }
                }
            }
        }

        // Converts v12 exports, if necessary.
        private func tryConvertFile(_ data: Data) -> Data {
            print("Trying to convert file")
            // Attempt to parse the JSON data into a mutable dictionary.
            guard
                var jsonObject = try? JSONSerialization.jsonObject(
                    with: data,
                    options: .mutableContainers
                ) as? [String: Any]
            else {
                // If it's not valid JSON, return the original data.
                return data
            }
            
            guard let exportSource = jsonObject["exportSource"] as? String,
                  exportSource == "iOS Journal"
                    || exportSource == "Android Journal"
            else {
                return data
            }
            
            print("Converting from v12+ iOS Journal")
            
            jsonObject.removeValue(forKey: "exportSource")
            
            let customUnits =
            (jsonObject["customUnits"] as? [[String: Any]]) ?? []
            
            // Transform 'customUnits' into the old 'customSubstances' format.
            let customSubstances = customUnits.map { unit -> [String: Any] in
                let name = unit["name"] as? String ?? ""
                let units = unit["unit"] as? String ?? ""
                let description = unit["note"] as? String ?? ""
                return [
                    "name": name,
                    "units": units,
                    "description": description,
                ]
            }
            jsonObject["customSubstances"] = customSubstances
            
            // Build list of substance companions
            var companionObject = (jsonObject["substanceCompanions"] as? [[String: String]]) ?? []
            
            let companions: [String] = companionObject.map { companion in
                companion["substanceName"] ?? ""
            }.filter { substance in
                substance != ""
            }
            
            // First pass: Build an initial map of Int ID -> (substanceName, nested customUnitId)
            var customUnitSubstancesMap:
            [Int: (substanceName: String?, customUnitId: Int?)] = [:]
            for unit in customUnits {
                let idInt: Int
                
                // Convert ID to Int, handling both String and Int cases
                if let id = unit["id"] as? Int {
                    idInt = id
                } else if let id = unit["id"] as? String,
                          let convertedId = Int(id)
                {
                    idInt = convertedId
                } else {
                    continue
                }
                
                let name = unit["name"] as? String
                
                if let color = unit["color"] as? String {
                    if let name = name {
                        if (!companions.contains(name)) {
                            let companion: [String: String] = ["substanceName": name, "color": color]
                            companionObject.append(companion)
                        }
                    }
                }
                
                if let doseComponents = unit["doseComponents"]
                    as? [[String: Any]],
                   let firstComponent = doseComponents.first
                {
                    let substanceName =
                    firstComponent["substanceName"] as? String
                    
                    // Handle customUnitId as Int or string
                    let customUnitIdInt: Int?
                    if let customUnitId = firstComponent["customUnitId"] as? Int
                    {
                        customUnitIdInt = customUnitId
                    } else if let customUnitId = firstComponent["customUnitId"]
                                as? String, let convertedId = Int(customUnitId)
                    {
                        customUnitIdInt = convertedId
                    } else {
                        customUnitIdInt = nil
                    }
                    
                    customUnitSubstancesMap[idInt] = (
                        substanceName, customUnitIdInt
                    )
                } else {
                    customUnitSubstancesMap[idInt] = (name, nil)
                }
            }
            
            jsonObject.updateValue(companionObject, forKey: "substanceCompanions")
            
            // Second pass: Resolve the nested references into a final, simple mapping.
            var resolvedMapping: [Int: String] = [:]
            for (key, value) in customUnitSubstancesMap {
                if let nestedId = value.customUnitId,
                   let resolvedValue = customUnitSubstancesMap[nestedId]
                {
                    resolvedMapping[key] =
                    resolvedValue.substanceName ?? value.substanceName
                    ?? "Unknown Substance"
                } else {
                    resolvedMapping[key] =
                    value.substanceName ?? "Unknown Substance"
                }
            }
            jsonObject.removeValue(forKey: "customUnits")
            
            // Update ingestions within experiences to use the resolved substance names.
            if var experiences = jsonObject["experiences"] as? [[String: Any]] {
                for i in 0..<experiences.count {
                    var experience = experiences[i]
                    if var ingestions = experience["ingestions"]
                        as? [[String: Any]]
                    {
                        if ingestions.isEmpty {
                            continue
                        }
                        for j in 0..<ingestions.count {
                            var ingestion = ingestions[j]
                            
                            // Check for missing/null substanceName
                            if ingestion["substanceName"] == nil
                                || (ingestion["substanceName"] as? NSNull)
                                != nil {
                                
                                let customUnitIdInt: Int?
                                if let intId = ingestion["customUnitId"] as? Int
                                {
                                    customUnitIdInt = intId
                                } else if let stringId = ingestion[
                                    "customUnitId"
                                ] as? String, let convertedId = Int(stringId) {
                                    customUnitIdInt = convertedId
                                } else {
                                    customUnitIdInt = nil
                                }
                                
                                if let customUnitId = customUnitIdInt,
                                   let resolvedName = resolvedMapping[
                                    customUnitId
                                   ]
                                {
                                    ingestion["substanceName"] = resolvedName
                                } else {
                                    ingestion["substanceName"] =
                                    "Unknown Substance3"
                                }
                            }
                            ingestions[j] = ingestion
                        }
                        experience["ingestions"] = ingestions
                        experiences[i] = experience
                    }
                }
                jsonObject["experiences"] = experiences
            }
            
            do {
                let finalData = try JSONSerialization.data(
                    withJSONObject: jsonObject
                )
                print("Successfully re-serialized converted JSON.")
                return finalData
            } catch {
                print("Failed to re-serialize converted JSON: \(error)")
                return data
            }
        }
        // swiftlint:enable cyclomatic_complexity function_body_length

        func deleteEverything() {
            Task {
                do {
                    let context = PersistenceController.shared.viewContext
                    let fetchRequest = Ingestion.fetchRequest()
                    let allIngestions = try context.fetch(fetchRequest)

                    await withTaskGroup(of: Void.self) { group in
                        for ingestion in allIngestions {
                            group.addTask {
                                await FinishIngestionScreen.deleteWebhookMessageIfNeeded(for: ingestion)
                            }
                        }
                    }

                    try PersistenceController.shared.deleteEverything()
                    await MainActor.run {
                        showSuccessToast(message: "Delete Successful")
                    }
                } catch {
                    await MainActor.run {
                        showErrorToast(message: "Delete Failed")
                    }
                }
            }
        }

        private func showSuccessToast(message: String) {
            toastMessage = message
            isShowingToast = true
            isShowingSuccessToast = true
        }

        private func showErrorToast(message: String) {
            toastMessage = message
            isShowingToast = true
            isShowingSuccessToast = false
        }
    }
}
