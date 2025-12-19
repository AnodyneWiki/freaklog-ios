import Foundation

extension AddCustomSubstanceView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var name = ""
        @Published var explanation = ""
        @Published var units: String = UnitPickerOptions.mg.rawValue

        var isEverythingNeededDefined: Bool {
            guard !name.isEmpty else { return false }
            guard !units.isEmpty else { return false }
            return true
        }

        func saveCustom(onComplete: (() -> Void)) {
            assert(isEverythingNeededDefined, "Tried to save custom substance without defining the necessary fields")
            let context = PersistenceController.shared.viewContext
            let nameValue = name
            let unitsValue = units
            let explanationValue = explanation
            context.performAndWait {
                let custom = CustomSubstance(context: context)
                custom.name = nameValue
                custom.units = unitsValue
                custom.explanation = explanationValue.isEmpty ? nil : explanationValue
                try? context.save()
                onComplete()
            }
        }
    }
}
