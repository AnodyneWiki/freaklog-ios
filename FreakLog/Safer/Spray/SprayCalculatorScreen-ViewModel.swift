@preconcurrency import CoreData

extension SprayCalculatorScreen {
    @MainActor
    class ViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
        private let sprayFetchController: NSFetchedResultsController<Spray>

        @Published private(set) var sprayModels: [SprayModel] = []
        @Published private(set) var selectedSpray: SprayModel?
        @Published private(set) var calculation: SprayCalculation = .soluteWeight
        @Published var units = WeightUnit.mg {
            didSet {
                guard oldValue != units else { return }
                weightPerSprayText = ""
                if calculation == .liquidVolume { knownQuantityText = "" }
            }
        }
        @Published var weightPerSprayText = ""
        @Published var knownQuantityText = ""
        @Published var purityInPercentText = ""
        @Published var isShowingAddSpray = false
        @Published var errorMessage: String?

        var weightPerSpray: Double? { SprayCalculation.positiveNumber(weightPerSprayText) }
        var knownQuantity: Double? { SprayCalculation.positiveNumber(knownQuantityText) }

        var purity: Double? {
            guard let value = SprayCalculation.positiveNumber(purityInPercentText), value <= 100 else { return nil }
            return value
        }

        var result: Double? {
            guard let selectedSpray, let knownQuantity, let weightPerSpray else { return nil }
            return calculation.result(knownQuantity: knownQuantity, weightPerSpray: weightPerSpray, spray: selectedSpray)
        }

        var adjustedWeight: Double? {
            let weight = calculation == .soluteWeight ? result : (result == nil ? nil : knownQuantity)
            guard let weight, let purity else { return nil }
            return SprayCalculation.adjustedWeight(weight, purity: purity)
        }

        override init() {
            sprayFetchController = NSFetchedResultsController(
                fetchRequest: PersistenceController.sprayRequest(),
                managedObjectContext: PersistenceController.shared.viewContext,
                sectionNameKeyPath: nil, cacheName: nil
            )
            super.init()
            sprayFetchController.delegate = self
            do {
                try sprayFetchController.performFetch()
                assignToSprayModels(sprays: sprayFetchController.fetchedObjects ?? [])
            } catch {
                errorMessage = "Couldn’t load saved sprays."
            }
        }

        func selectCalculation(_ next: SprayCalculation) {
            guard next != calculation else { return }
            knownQuantityText = result?.formatted(.number.grouping(.never).precision(.significantDigits(1...15))) ?? ""
            calculation = next
        }

        public nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
            Task { @MainActor in
                guard let sprays = controller.fetchedObjects as? [Spray] else { return }
                assignToSprayModels(sprays: sprays)
            }
        }

        func select(_ model: SprayModel) {
            guard model.isValid, selectedSpray?.id != model.id, let spray = model.spray else { return }
            do {
                try PersistenceController.withJournalStoreWrite {
                    let context = try PersistenceController.shared.journalEditContext()
                    let preferred = try PersistenceController.journalObject(spray, in: context)
                    for other in try context.fetch(PersistenceController.sprayRequest()) where other.isPreferred && other != preferred {
                        other.isPreferred = false
                    }
                    preferred.isPreferred = true
                    try context.save()
                }
                selectedSpray = model
            } catch {
                errorMessage = "Couldn’t select this spray. \(error.localizedDescription)"
            }
        }

        func deleteSprays(at offsets: IndexSet) {
            let sprays = offsets.compactMap { index in
                sprayModels.indices.contains(index) ? sprayModels[index].spray : nil
            }
            guard !sprays.isEmpty else { return }
            do {
                try PersistenceController.withJournalStoreWrite {
                    let context = try PersistenceController.shared.journalEditContext()
                    for spray in sprays {
                        context.delete(try PersistenceController.journalObject(spray, in: context))
                    }
                    try context.save()
                }
            } catch {
                errorMessage = "Couldn’t delete these sprays. \(error.localizedDescription)"
            }
        }

        private func assignToSprayModels(sprays: [Spray]) {
            sprayModels = sprays.map { spray in
                SprayModel(name: spray.nameUnwrapped, numSprays: spray.numSprays, contentInMl: spray.contentInMl, spray: spray)
            }
            selectedSpray = sprayModels.first { $0.isValid && $0.spray?.isPreferred == true }
                ?? sprayModels.first { $0.isValid }
        }
    }
}
