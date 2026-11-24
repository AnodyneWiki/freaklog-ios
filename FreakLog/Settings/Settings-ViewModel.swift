import CoreData
import Foundation

extension SettingsScreen {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var isExporting = false
        @Published var journalFile = JournalFile(experiences: [], customSubstances: [], customUnits: [])
        weak var toastViewModel: ToastViewModel?

        func exportData() {
            let pc = PersistenceController.shared
            journalFile = JournalFile(
                experiences: pc.getAllExperiences(),
                customSubstances: pc.getAllCustomSubstances(),
                customUnits: pc.getAllCustomUnits(),
                substanceOverrideRoas: pc.getAllStandaloneCustomRoas(),
                substanceOverrides: (try? pc.viewContext.fetch(PersistenceController.substanceOverridesRequest())) ?? [],
                formulations: pc.getAllFormulations())
            isExporting = true
        }

        // swiftlint:disable cyclomatic_complexity function_body_length
        func importData(data: Data) {
            Task {
                do {
                    let container = PersistenceController.shared.container
                    
                    // Decode off the main thread first; the view model, and so this task, is main-actor isolated
                    let file = try await Task.detached(priority: .userInitiated) {
                        try JSONDecoder().decode(JournalFile.self, from: Self.tryConvertFile(data))
                    }.value
                    
                    await container.performBackgroundTask { context in
                        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                        
                        do {
                            // First delete everything in this background context
                            try PersistenceController.shared.deleteEverything(blockContext: context)
                            
                            file.insert(into: context)
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
        private nonisolated static func tryConvertFile(_ data: Data) -> Data {
            guard
                var jsonObject = try? JSONSerialization.jsonObject(
                    with: data,
                    options: .mutableContainers
                ) as? [String: Any]
            else {
                return data
            }
            
            guard let exportSource = jsonObject["exportSource"] as? String,
                  exportSource == "iOS Journal"
                    || exportSource == "Android Journal"
            else {
                return data
            }
            
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
                                    ingestion["substanceName"] = "Unknown Substance"
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
                return finalData
            } catch {
                return data
            }
        }
        // swiftlint:enable cyclomatic_complexity function_body_length

        func deleteEverything() {
            Task {
                do {
                    let cleanUp = await IngestionDeletion.remoteCleanUp(for: PersistenceController.shared.getAllIngestions())
                    try PersistenceController.shared.deleteEverything()
                    cleanUp()
                    showSuccessToast(message: "Delete Successful")
                } catch {
                    showErrorToast(message: "Delete Failed")
                }
            }
        }

        private func showSuccessToast(message: String) {
            toastViewModel?.showSuccessToast(message: message)
        }

        private func showErrorToast(message: String) {
            toastViewModel?.showErrorToast(message: message)
        }
    }
}
