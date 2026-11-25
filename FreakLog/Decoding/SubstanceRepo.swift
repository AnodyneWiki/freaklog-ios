import CoreData
import Foundation

struct SubstanceRepo {
    static let shared = SubstanceRepo()

    let substances: [Substance]
    let categories: [Category]
    private let substancesDict: [String: Substance]
    private let identityOnlyNames: Set<String>

    init() {
        let data = SubstanceRepo.getInitialData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.keyDecodingStrategy = .useDefaultKeys
        // swiftlint:disable force_try
        let file = try! decoder.decode(SubstanceFile.self, from: data)
        // swiftlint:enable force_try
        substances = file.substances
        categories = file.categories
        substancesDict = Dictionary(
            uniqueKeysWithValues: substances.map { substance in
                (substance.name, substance)
            }
        )
        identityOnlyNames = Set(substances.filter { !$0.usesWikiReferences }.map { $0.name.lowercased() })
    }

    func getSubstance(name: String) -> Substance? {
        substancesDict[name]
    }

    func usesWikiReferences(for name: String) -> Bool {
        !identityOnlyNames.contains(name.lowercased())
    }

    func getSubstances<C: Collection>(names: C) -> [Substance] where C.Element == String {
        let names = Set(names)
        return substances.filter { names.contains($0.name) }
    }

    private static func getInitialData() -> Data {
        let fileName = "substances"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            fatalError("Failed to locate \(fileName) in bundle.")
        }
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Failed to load \(fileName) from bundle.")
        }
        return data
    }
}
