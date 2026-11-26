import CoreData
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct JournalPreset: Codable, Identifiable {
    static let formatName = "woof.freaklog.preset"
    static let currentFormatVersion = 2
    private static let maximumFileSize = 2_000_000

    let format: String
    let formatVersion: Int
    let unit: CustomUnitCodable?
    let formulation: FormulationCodable?
    let substances: [CustomSubstanceCodable]
    let standaloneSubstance: CustomSubstanceCodable?
    let palette: [PaletteColor]?

    var id: String { name }
    var name: String { unit?.name ?? formulation?.name ?? standaloneSubstance?.name ?? "Substance Palette" }
    var kind: String {
        if palette != nil { return "Substance Palette" }
        if standaloneSubstance != nil { return "Custom Substance" }
        return unit == nil ? "Formulation" : "Custom Unit"
    }
    var ingredientNames: [String] { unit.map { [$0.substanceName] } ?? formulation?.substanceNames ?? [] }

    struct PaletteColor: Codable, Equatable, Identifiable {
        let substanceName: String
        let color: SubstanceColor

        var id: String { substanceName }
    }

    init(unit: CustomUnit? = nil, formulation: Formulation? = nil, in context: NSManagedObjectContext) throws {
        let unit = unit.map { CustomUnitCodable($0, id: 0) }
        let formulation = formulation.map(FormulationCodable.init)
        let ingredientNames = unit.map { [$0.substanceName] } ?? formulation?.substanceNames ?? []
        format = Self.formatName
        formatVersion = 1
        self.unit = unit
        self.formulation = formulation
        standaloneSubstance = nil
        palette = nil
        substances = try context.fetch(PersistenceController.customSubstancesRequest())
            .filter { ingredientNames.contains($0.nameUnwrapped) }
            .map(CustomSubstanceCodable.init)
        try validate()
    }

    init(customSubstance: CustomSubstanceCodable) throws {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        unit = nil
        formulation = nil
        substances = []
        standaloneSubstance = customSubstance
        palette = nil
        try validate()
    }

    init(palette: [PaletteColor]) throws {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        unit = nil
        formulation = nil
        substances = []
        standaloneSubstance = nil
        self.palette = palette
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
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw ImportError.tooLarge }
        return ExportedFile(data: data, filename: palette == nil ? "FreakLog Preset.json" : "FreakLog Palette.json")
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
        if standaloneSubstance != nil {
            let names = try reservedSubstanceNames(in: context)
            guard names.contains(where: { Self.comparisonKey($0) == Self.comparisonKey(name) }) else { return name }
            var copyName = "\(name) (Copy)"
            var ordinal = 2
            while names.contains(where: { Self.comparisonKey($0) == Self.comparisonKey(copyName) }) {
                copyName = "\(name) (Copy \(ordinal))"
                ordinal += 1
            }
            return copyName
        }
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
            try validate()
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let standaloneSubstance {
                guard !name.isEmpty, !(try reservedSubstanceNames(in: context)).contains(where: {
                    Self.comparisonKey($0) == Self.comparisonKey(name)
                }) else { throw ImportError.nameTaken }
                let definition = CustomSubstanceCodable(name: name, units: standaloneSubstance.units,
                                                        description: standaloneSubstance.description,
                                                        roas: standaloneSubstance.roas)
                do {
                    let substance = definition.insert(into: context)
                    try context.save()
                    return substance.objectID
                } catch {
                    context.rollback()
                    throw error
                }
            }
            guard palette == nil else { throw ImportError.invalid }
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

    struct PaletteReviewRow: Equatable, Identifiable {
        let entry: PaletteColor
        let originalColors: Set<SubstanceColor>
        let isKnownSubstance: Bool

        var id: String { entry.substanceName }
        var hasConflict: Bool { originalColors.contains { $0 != entry.color } }
        var isAlreadySet: Bool { originalColors == [entry.color] }
    }

    func reviewPalette(in context: NSManagedObjectContext) throws -> [PaletteReviewRow] {
        guard let palette else { throw ImportError.invalid }
        let rows = try context.fetch(PersistenceController.substanceCompanionsRequest())
        let companions = Dictionary(grouping: rows, by: \.substanceNameUnwrapped)
        let customNames = Set(try context.fetch(PersistenceController.customSubstancesRequest()).map(\.nameUnwrapped))
        return palette.map { entry in
            let name = entry.substanceName
            let records = companions[name, default: []]
            return PaletteReviewRow(
                entry: entry, originalColors: Set(records.map(\.color)),
                isKnownSubstance: !records.isEmpty || customNames.contains(name)
                    || SubstanceRepo.shared.getSubstance(name: name) != nil
            )
        }
    }

    func importPalette(_ reviewed: [PaletteReviewRow], replacing selected: Set<String>,
                       in context: NSManagedObjectContext) throws {
        try PersistenceController.withJournalStoreWrite {
            try validate()
            guard try reviewPalette(in: context) == reviewed else { throw ImportError.paletteChanged }
            let changes = reviewed.filter { row in
                row.isKnownSubstance && !row.isAlreadySet && (!row.hasConflict || selected.contains(row.id))
            }
            guard !changes.isEmpty else { return }
            let request = PersistenceController.substanceCompanionsRequest()
            request.predicate = NSPredicate(format: "substanceName IN %@", changes.map(\.id))
            let companions = Dictionary(grouping: try context.fetch(request), by: \.substanceNameUnwrapped)
            do {
                for row in changes {
                    if let existing = companions[row.id] {
                        for companion in existing { companion.colorAsText = row.entry.color.rawValue }
                    } else {
                        _ = CompanionCodable(substanceName: row.id, color: row.entry.color).insert(into: context)
                    }
                }
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func reservedSubstanceNames(in context: NSManagedObjectContext) throws -> Set<String> {
        let builtIn = SubstanceRepo.shared.substances.map(\.name)
        let custom = try context.fetch(PersistenceController.customSubstancesRequest()).map(\.nameUnwrapped)
        let historical = try context.fetch(PersistenceController.substanceCompanionsRequest()).map(\.substanceNameUnwrapped)
        return Set(builtIn + custom + historical)
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
        guard (1...Self.currentFormatVersion).contains(formatVersion) else { throw ImportError.unsupportedVersion }
        if standaloneSubstance != nil || palette != nil {
            guard formatVersion == 2, unit == nil, formulation == nil, substances.isEmpty,
                  (standaloneSubstance != nil) != (palette != nil) else { throw ImportError.invalid }
            if let standaloneSubstance {
                guard !Self.comparisonKey(standaloneSubstance.name).isEmpty,
                      !standaloneSubstance.units.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ImportError.invalid
                }
            }
            if let palette {
                let names = palette.map { Self.comparisonKey($0.substanceName) }
                guard !names.isEmpty, !names.contains(""), Set(names).count == names.count else {
                    throw ImportError.invalid
                }
            }
            return
        }
        guard (unit != nil) != (formulation != nil), !Self.comparisonKey(name).isEmpty,
              !ingredientNames.isEmpty, !ingredientNames.contains(where: { Self.comparisonKey($0).isEmpty }),
              (formulation?.components.count ?? 0) < Int(Int16.max) else { throw ImportError.invalid }
        let dependencyNames = Set(substances.map(\.name))
        guard dependencyNames.count == substances.count, dependencyNames.isSubset(of: Set(ingredientNames)) else {
            throw ImportError.invalid
        }
    }

    private enum ImportError: LocalizedError {
        case invalid, tooLarge, unsupportedVersion, nameTaken, missingDependency, conflict, paletteChanged

        var errorDescription: String? {
            switch self {
            case .invalid: "This file isn’t a valid FreakLog preset."
            case .tooLarge: "The preset file is too large."
            case .unsupportedVersion: "This preset format version isn’t supported."
            case .nameTaken: "Enter a different name. A preset with this name already exists."
            case .missingDependency: "An ingredient definition is missing."
            case .conflict: "Review the existing ingredient definitions before importing."
            case .paletteChanged: "Your local colors changed during review. Open the palette again to compare them."
            }
        }
    }
}

enum JournalPresetProduct: Hashable {
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
            JournalPresetFileShare(file: file, name: product.name, title: title)
        }
    }
}

struct JournalPresetFileShare: View {
    let file: ExportedFile
    let name: String
    var title: LocalizedStringKey = "Share Preset"

    var body: some View {
        ShareLink(item: ShareablePreset(data: file.data), preview: SharePreview(name)) {
            Label(title, systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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
    enum Scope {
        case products, palette, all

        func accepts(_ preset: JournalPreset) -> Bool {
            switch self {
            case .products: preset.unit != nil || preset.formulation != nil
            case .palette: preset.palette != nil
            case .all: true
            }
        }

        var unavailableMessage: String {
            switch self {
            case .products: "Choose a custom unit or formulation preset for this container."
            case .palette: "Choose a substance palette file."
            case .all: "This preset can’t be imported here."
            }
        }
    }

    @Binding var isPresented: Bool
    var scope: Scope = .products
    var onImported: (NSManagedObjectID) -> Void = { _ in }

    @State private var importPreset: JournalPreset?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                do {
                    let preset = try JournalPreset.read(result.get())
                    if scope.accepts(preset) {
                        error = nil
                        importPreset = preset
                    } else {
                        error = scope.unavailableMessage
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .sheet(item: $importPreset) { preset in
                if preset.palette != nil {
                    PalettePresetImportReview(preset: preset)
                } else {
                    JournalPresetImportReview(preset: preset, onImported: onImported)
                }
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
    @FetchRequest(fetchRequest: PersistenceController.customSubstancesRequest())
    private var customSubstances: FetchedResults<CustomSubstance>

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
                Text("Share products and their ingredients, standalone substance definitions, or colors.")
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
            Section("Custom Substances") {
                if customSubstances.isEmpty { Text("No custom substances").foregroundStyle(.secondary) }
                ForEach(customSubstances) { substance in
                    if let file = try? JournalPreset(customSubstance: .init(substance)).exportFile() {
                        JournalPresetFileShare(file: file, name: substance.nameUnwrapped,
                                               title: LocalizedStringKey(substance.nameUnwrapped))
                    }
                }
            }
            Section {
                NavigationLink("Review Palette to Share") { PalettePresetExportScreen() }
            }
        }
        .navigationTitle("Share Presets")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(JournalPresetImporter(isPresented: $isImporting, scope: .all))
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
                } else if let definition = preset.standaloneSubstance {
                    Section {
                        LabeledContent("Units", value: definition.units)
                        if !definition.description.isEmpty { Text(definition.description) }
                        ForEach(Array(definition.roas.enumerated()), id: \.offset) { _, route in
                            LabeledContent("Saved Route", value: route.administrationRoute.rawValue.localizedCapitalized)
                        }
                    } header: {
                        Text("Definition")
                    } footer: {
                        Text("Choose a unique name to add this definition to your journal.")
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

struct PalettePresetExportScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    private var companions: FetchedResults<SubstanceCompanion>
    @State private var omitted: Set<String> = []

    private var colors: [JournalPreset.PaletteColor] {
        Dictionary(grouping: companions, by: \.substanceNameUnwrapped)
            .compactMap { name, rows in
                guard let color = rows.first?.color,
                      rows.allSatisfy({ $0.color == color }),
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return .init(substanceName: name, color: color)
            }
            .sorted { $0.substanceName.localizedStandardCompare($1.substanceName) == .orderedAscending }
    }

    var body: some View {
        let colors = colors
        let selected = colors.filter { !omitted.contains($0.id) }
        Form {
            Section {
                if colors.isEmpty {
                    Text("No colors to share").foregroundStyle(.secondary)
                }
                ForEach(colors) { entry in
                    Toggle(isOn: Binding(get: { !omitted.contains(entry.id) }, set: { includes in
                        if includes { omitted.remove(entry.id) } else { omitted.insert(entry.id) }
                    })) {
                        PaletteSwatch(entry: entry)
                    }
                }
            } header: {
                Text("Colors to Include")
            } footer: {
                Text("The file contains only the selected substance names and colors.")
            }
            if !selected.isEmpty, (try? JournalPreset(palette: selected).exportFile()) == nil {
                Text("Choose a single color for each substance.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Share Palette")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let file = try? JournalPreset(palette: selected).exportFile() {
                ToolbarItem(placement: .confirmationAction) {
                    JournalPresetFileShare(file: file, name: "Substance Palette", title: "Share")
                }
            }
        }
    }
}

private struct PalettePresetImportReview: View {
    let preset: JournalPreset
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastViewModel
    @State private var rows: [JournalPreset.PaletteReviewRow] = []
    @State private var replacements: Set<String> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(rows) { row in
                        if row.hasConflict {
                            Toggle(isOn: Binding(get: { replacements.contains(row.id) }, set: { useIncoming in
                                if useIncoming { replacements.insert(row.id) } else { replacements.remove(row.id) }
                            })) {
                                PaletteSwatch(entry: row.entry, detail: replacementSummary(row))
                            }
                        } else {
                            PaletteSwatch(entry: row.entry,
                                          detail: row.isAlreadySet ? "Already matches" :
                                            (row.isKnownSubstance ? "Add color" : "Substance unavailable"))
                        }
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                    }
                } footer: {
                    Text("Apply colors to substances available in your journal.")
                }
            }
            .navigationTitle("Review Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: save)
                        .disabled(!rows.contains {
                            $0.isKnownSubstance && !$0.isAlreadySet && (!$0.hasConflict || replacements.contains($0.id))
                        })
                }
            }
            .task {
                do { rows = try preset.reviewPalette(in: viewContext) }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save() {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            try preset.importPalette(rows, replacing: replacements, in: context)
            toast.showSuccessToast(message: "Palette Imported")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func replacementSummary(_ row: JournalPreset.PaletteReviewRow) -> String {
        let current = ListFormatter.localizedString(byJoining: row.originalColors.map(\.name).sorted())
        return String(localized: "Replace \(current) with \(row.entry.color.name)")
    }
}

private struct PaletteSwatch: View {
    let entry: JournalPreset.PaletteColor
    var detail: String? = nil

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.substanceName)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: "circle.fill")
                .foregroundStyle(entry.color.swiftUIColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(entry.color.name)
    }
}
