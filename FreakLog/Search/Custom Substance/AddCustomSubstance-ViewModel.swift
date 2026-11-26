import CoreData
import Foundation

extension AddCustomSubstanceView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var name = ""
        @Published var explanation = ""
        @Published var units: String = UnitPickerOptions.mg.rawValue

        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isEverythingNeededDefined: Bool {
            guard !trimmedName.isEmpty else { return false }
            guard !units.isEmpty else { return false }
            return true
        }

        func saveCustom() throws -> AddIngestionSubstance {
            let context = try PersistenceController.shared.journalEditContext()
            let existing = PersistenceController.customSubstancesRequest()
            let alreadyExists = try context.fetch(existing).contains { SimilarSubstanceNames.isSameName($0.nameUnwrapped, trimmedName) }
            guard !alreadyExists,
                  !SubstanceRepo.shared.substances.contains(where: { SimilarSubstanceNames.isSameName($0.name, trimmedName) })
            else { throw SimilarSubstanceError.nameTaken }
            let custom = CustomSubstance(context: context)
            custom.name = trimmedName
            custom.units = units
            custom.explanation = explanation.isEmpty ? nil : explanation
            try context.save()
            return .custom(name: trimmedName, units: units)
        }
    }
}

enum SimilarSubstanceNames {
    private static func folded(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func isSameName(_ first: String, _ second: String) -> Bool {
        folded(first) == folded(second)
    }

    static func distance(_ first: String, _ second: String) -> Int? {
        let left = Array(folded(first).filter { $0.isLetter || $0.isNumber })
        let right = Array(folded(second).filter { $0.isLetter || $0.isNumber })
        guard !left.isEmpty, !right.isEmpty else { return nil }
        if left == right { return 0 }
        let length = min(left.count, right.count)
        guard length >= 5, left.filter(\.isNumber) == right.filter(\.isNumber) else { return nil }
        let limit = max(left.count, right.count) / 4
        guard abs(left.count - right.count) <= limit else { return nil }
        var previous = Array(0...right.count)
        for (index, letter) in left.enumerated() {
            var row = [index + 1]
            for (column, otherLetter) in right.enumerated() {
                let replacement = previous[column] + (letter == otherLetter ? 0 : 1)
                row.append(min(replacement, previous[column + 1] + 1, row[column] + 1))
            }
            previous = row
        }
        return previous[right.count] <= limit ? previous[right.count] : nil
    }
}

enum SimilarSubstanceError: LocalizedError {
    case nameTaken
    case changed

    var errorDescription: String? {
        switch self {
        case .nameTaken: "This name is already in the substance library."
        case .changed: "One of these substances changed. Reopen the review for the latest details."
        }
    }
}
