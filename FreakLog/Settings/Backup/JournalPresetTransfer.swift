import CoreData
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct JournalPreset: Codable, Identifiable {
    static let formatName = "woof.freaklog.preset"
    static let currentFormatVersion = 1
    private static let maximumFileSize = 2_000_000

    let format: String
    let formatVersion: Int
    let unit: CustomUnitCodable?
    let formulation: FormulationCodable?
    let substances: [CustomSubstanceCodable]

    var id: String { name }
    var name: String { unit?.name ?? formulation?.name ?? "" }
    var kind: String { unit == nil ? "Formulation" : "Custom Unit" }
    var ingredientNames: [String] { unit.map { [$0.substanceName] } ?? formulation?.substanceNames ?? [] }

    init(unit: CustomUnit? = nil, formulation: Formulation? = nil, in context: NSManagedObjectContext) throws {
        let unit = unit.map { CustomUnitCodable($0, id: 0) }
        let formulation = formulation.map(FormulationCodable.init)
        let ingredientNames = unit.map { [$0.substanceName] } ?? formulation?.substanceNames ?? []
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        self.unit = unit
        self.formulation = formulation
        substances = try context.fetch(PersistenceController.customSubstancesRequest())
            .filter { ingredientNames.contains($0.nameUnwrapped) }
            .map(CustomSubstanceCodable.init)
        try validate()
    }

    static func read(_ url: URL) throws -> JournalPreset {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: maximumFileSize + 1), data.count <= maximumFileSize else {
            throw ImportError.tooLarge
        }
        let preset: JournalPreset
        do {
            preset = try JSONDecoder().decode(JournalPreset.self, from: data)
        } catch {
            throw ImportError.invalid
        }
        try preset.validate()
        return preset
    }

    func exportFile() throws -> ExportedFile {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw ImportError.tooLarge }
        return ExportedFile(data: data, filename: "FreakLog Preset.json")
    }

    struct Dependency: Identifiable {
        enum Status {
            case add
            case reuse
            case conflict
            case unavailable

            var label: String {
                switch self {
                case .add: "Add"
                case .reuse: "Already available"
                case .conflict: "Keep local definition"
                case .unavailable: "Missing definition"
                }
            }
        }

        let name: String
        let status: Status

        var id: String { name }
    }

    func dependencies(in context: NSManagedObjectContext) throws -> [Dependency] {
        let local = try context.fetch(PersistenceController.customSubstancesRequest())
        return ingredientNames.map { name in
            let incoming = substances.first { $0.name == name }
            // A differently spelled or capitalized name has a different journal key.
            let exact = local.filter { $0.nameUnwrapped == name }
            let builtin = SubstanceRepo.shared.getSubstance(name: name)
            let status: Dependency.Status
            if let incoming {
                if !exact.isEmpty {
                    let agrees = exact.contains { substance in
                        let stored = CustomSubstanceCodable(substance)
                        return incoming.units == stored.units && incoming.description == stored.description
                            && incoming.roas == stored.roas
                    }
                    status = agrees ? .reuse : .conflict
                } else if builtin != nil {
                    status = .conflict
                } else {
                    status = .add
                }
            } else {
                status = (builtin != nil || !exact.isEmpty) ? .reuse : .unavailable
            }
            return Dependency(name: name, status: status)
        }
    }

    func availableName(in context: NSManagedObjectContext) throws -> String {
        let names = try existingNames(in: context)
        guard names.contains(Self.comparisonKey(name)) else { return name }
        var name = "\(self.name) (Copy)"
        var ordinal = 2
        while names.contains(Self.comparisonKey(name)) {
            name = "\(self.name) (Copy \(ordinal))"
            ordinal += 1
        }
        return name
    }

    @discardableResult
    func importInto(_ context: NSManagedObjectContext, as name: String, keepLocalDefinitions: Bool) throws -> NSManagedObjectID {
        try PersistenceController.withJournalStoreWrite {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !((try existingNames(in: context)).contains(Self.comparisonKey(name))) else {
                throw ImportError.nameTaken
            }
            let dependencies = try dependencies(in: context)
            guard !dependencies.contains(where: { $0.status == .unavailable }) else { throw ImportError.missingDependency }
            guard keepLocalDefinitions || !dependencies.contains(where: { $0.status == .conflict }) else {
                throw ImportError.conflict
            }
            do {
                let newNames = Set(dependencies.filter { $0.status == .add }.map(\.name))
                for substance in substances where newNames.contains(substance.name) {
                    _ = substance.insert(into: context)
                }
                let inserted: NSManagedObject
                if let unit {
                    let units = try context.fetch(CustomUnit.fetchRequest())
                    let reserved = Set(units.map(\.idForAndroid))
                    var id: Int32 = 1
                    while reserved.contains(id) {
                        guard id < .max else { throw ImportError.invalid }
                        id += 1
                    }
                    let customUnit = unit.insert(into: context)
                    customUnit.name = name
                    customUnit.idForAndroid = id
                    customUnit.isArchived = false
                    inserted = customUnit
                } else if var formulation {
                    formulation.name = name
                    inserted = formulation.insert(into: context)
                } else {
                    throw ImportError.invalid
                }
                try context.save()
                return inserted.objectID
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func existingNames(in context: NSManagedObjectContext) throws -> Set<String> {
        let names: [String]
        if unit != nil {
            names = try context.fetch(CustomUnit.fetchRequest()).map(\.nameUnwrapped)
        } else {
            names = try context.fetch(PersistenceController.formulationsRequest()).map(\.nameUnwrapped)
        }
        return Set(names.map(Self.comparisonKey))
    }

    private static func comparisonKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validate() throws {
        guard format == Self.formatName else { throw ImportError.invalid }
        guard formatVersion == Self.currentFormatVersion else { throw ImportError.unsupportedVersion }
        guard (unit != nil) != (formulation != nil), !Self.comparisonKey(name).isEmpty,
              !ingredientNames.isEmpty, !ingredientNames.contains(where: { Self.comparisonKey($0).isEmpty }),
              (formulation?.components.count ?? 0) < Int(Int16.max) else { throw ImportError.invalid }
        let dependencyNames = Set(substances.map(\.name))
        guard dependencyNames.count == substances.count, dependencyNames.isSubset(of: Set(ingredientNames)) else {
            throw ImportError.invalid
        }
    }

    private enum ImportError: LocalizedError {
        case invalid, tooLarge, unsupportedVersion, nameTaken, missingDependency, conflict

        var errorDescription: String? {
            switch self {
            case .invalid: "This file isn’t a valid FreakLog preset."
            case .tooLarge: "The preset file is too large."
            case .unsupportedVersion: "This preset format version isn’t supported."
            case .nameTaken: "Enter a different name. A preset with this name already exists."
            case .missingDependency: "An ingredient definition is missing."
            case .conflict: "Review the existing ingredient definitions before importing."
            }
        }
    }
}

enum JournalPresetProduct {
    case customUnit(CustomUnit)
    case formulation(Formulation)

    var name: String {
        switch self {
        case .customUnit(let unit): unit.nameUnwrapped
        case .formulation(let formulation): formulation.nameUnwrapped
        }
    }

    func preset(in context: NSManagedObjectContext) throws -> JournalPreset {
        switch self {
        case .customUnit(let unit): try JournalPreset(unit: unit, in: context)
        case .formulation(let formulation): try JournalPreset(formulation: formulation, in: context)
        }
    }
}

struct JournalPresetShareLink: View {
    @Environment(\.managedObjectContext) private var context
    let product: JournalPresetProduct
    var title: LocalizedStringKey = "Share Preset"

    var body: some View {
        if let file = try? product.preset(in: context).exportFile() {
            ShareLink(item: ShareablePreset(data: file.data), preview: SharePreview(product.name)) {
                Label(title, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    private struct ShareablePreset: Transferable {
        let data: Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .json) { preset in
                preset.data
            }
            .suggestedFileName("FreakLog Preset")
        }
    }
}

struct JournalPresetImporter: ViewModifier {
    @Binding var isPresented: Bool
    var onImported: (NSManagedObjectID) -> Void = { _ in }

    @State private var importPreset: JournalPreset?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                do {
                    importPreset = try JournalPreset.read(result.get())
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .sheet(item: $importPreset) { preset in
                JournalPresetImportReview(preset: preset, onImported: onImported)
            }
            .alert("Couldn’t Open Preset", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}

struct JournalPresetTransferScreen: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    private var units: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var document: ExportedFile?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
            }
            Section {
                Button {
                    error = nil
                    isImporting = true
                } label: {
                    Label("Import Preset", systemImage: "arrow.down.doc")
                }
            } footer: {
                Text("Presets include a product and its custom ingredients. They contain no journal entries.")
            }
            Section("Export Custom Unit") {
                if units.isEmpty { Text("No custom units").foregroundStyle(.secondary) }
                ForEach(units) { unit in
                    Button(unit.nameUnwrapped) { export(unit: unit) }
                }
            }
            Section("Export Formulation") {
                if formulations.isEmpty { Text("No formulations").foregroundStyle(.secondary) }
                ForEach(formulations) { formulation in
                    Button(formulation.nameUnwrapped) { export(formulation: formulation) }
                }
            }
        }
        .navigationTitle("Share Presets")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(JournalPresetImporter(isPresented: $isImporting))
        .fileExporter(
            isPresented: $isExporting, document: document,
            contentType: .json, defaultFilename: document?.filename
        ) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    private func export(unit: CustomUnit? = nil, formulation: Formulation? = nil) {
        error = nil
        do {
            let preset = try JournalPreset(unit: unit, formulation: formulation, in: context)
            document = try preset.exportFile()
            isExporting = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct JournalPresetImportReview: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastViewModel
    @State private var name = ""
    @State private var dependencies: [JournalPreset.Dependency] = []
    @State private var keepsLocalDefinitions = false
    @State private var isLoaded = false
    @State private var error: String?

    let preset: JournalPreset
    let onImported: (NSManagedObjectID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    LabeledContent("Type", value: preset.kind)
                    LabeledContent("Original Name", value: preset.name)
                    TextField("Import As", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let components = preset.formulation?.components {
                    Section("Contents") {
                        ForEach(components) { component in
                            LabeledContent {
                                Text(component.doseDescription()).monospacedDigit()
                            } label: {
                                Text(component.substanceName)
                                Text(component.administrationRoute.rawValue.localizedCapitalized)
                            }
                        }
                    }
                } else if let unit = preset.unit {
                    Section("Contents") {
                        LabeledContent("Substance", value: unit.substanceName)
                        LabeledContent("Route", value: unit.administrationRoute.rawValue.localizedCapitalized)
                        LabeledContent("Counting Unit", value: unit.unit)
                        LabeledContent("Amount per Unit") {
                            if let dose = unit.dose {
                                Text(dose.doseDescription(
                                    units: unit.originalUnit, isEstimate: unit.isEstimate,
                                    standardDeviation: unit.estimatedDoseStandardDeviation, rounded: true
                                ))
                            } else {
                                Text("Unknown")
                            }
                        }
                    }
                }
                if !dependencies.isEmpty {
                    Section("Ingredients") {
                        ForEach(dependencies) { dependency in
                            LabeledContent(dependency.name, value: dependency.status.label)
                        }
                        if hasConflict {
                            Toggle("Keep Existing Definitions", isOn: $keepsLocalDefinitions)
                        }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                }
            }
            .navigationTitle("Review Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: save)
                        .disabled(!isLoaded || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (hasConflict && !keepsLocalDefinitions)
                            || dependencies.contains { $0.status == .unavailable })
                }
            }
            .task {
                guard !isLoaded else { return }
                do {
                    name = try preset.availableName(in: viewContext)
                    dependencies = try preset.dependencies(in: viewContext)
                    isLoaded = true
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private var hasConflict: Bool { dependencies.contains { $0.status == .conflict } }

    private func save() {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let productID = try preset.importInto(context, as: name, keepLocalDefinitions: keepsLocalDefinitions)
            toast.showSuccessToast(message: "Preset Imported")
            onImported(productID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
