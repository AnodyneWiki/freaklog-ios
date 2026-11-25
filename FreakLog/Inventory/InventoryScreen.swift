import CoreData
import SwiftUI

struct InventoryScreen: View {
    private enum GroupKey: Hashable {
        case product(NSManagedObjectID)
        case title(String)

        var sortID: String {
            switch self {
            case .product(let id): id.uriRepresentation().absoluteString
            case .title(let title): title
            }
        }
    }

    private enum Grouping: String, CaseIterable, Identifiable {
        case product = "Product"
        case location = "Storage Location"
        case low = "Needs Attention"
        var id: Self { self }
        var title: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }

    @FetchRequest(fetchRequest: StockContainer.allRequest(), animation: .default)
    private var containers: FetchedResults<StockContainer>
    @State private var grouping: Grouping = .product
    @State private var addingContainer = false

    var body: some View {
        List {
            if containers.isEmpty {
                Section {
                    Label("No containers yet", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                    Button("Add Container") { addingContainer = true }
                }
            } else {
                Section {
                    Picker("Group by", selection: $grouping) {
                        ForEach(Grouping.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }

                let active = containers.filter { !$0.isArchived }
                if grouping == .low {
                    let needsAttention = active.filter { $0.isLow || $0.needsReview || $0.isExpired }
                    Section {
                        if needsAttention.isEmpty {
                            Text("No containers need attention.").foregroundStyle(.secondary)
                        }
                        rows(needsAttention)
                    }
                } else {
                    let groups = Dictionary(grouping: active, by: groupKey)
                    ForEach(groups.keys.sorted { lhs, rhs in
                        let order = groupTitle(groups[lhs] ?? []).localizedStandardCompare(groupTitle(groups[rhs] ?? []))
                        return order == .orderedSame ? lhs.sortID < rhs.sortID : order == .orderedAscending
                    }, id: \.self) { key in
                        let group = groups[key] ?? []
                        Section(header: Text(groupTitle(group))) {
                            if grouping == .product, let product = group.first?.inventoryProduct {
                                NavigationLink {
                                    ProductDetailScreen(product: product)
                                } label: {
                                    Label("Product Details", systemImage: "shippingbox")
                                }
                                .accessibilityLabel(Text("Details for \(product.name)"))
                            }
                            rows(group)
                        }
                    }
                }

                let archived = containers.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("Archived") { rows(archived) }
                }
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingContainer = true
                } label: {
                    Label("Add Container", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $addingContainer) {
            NavigationStack { StockContainerEditor() }
        }
    }

    private func groupKey(_ container: StockContainer) -> GroupKey {
        if grouping == .location { return .title(container.storageLabel) }
        if let product = container.inventoryProduct { return .product(product.object.objectID) }
        return .title(container.productName ?? container.displayName)
    }

    private func groupTitle(_ containers: [StockContainer]) -> String {
        guard let container = containers.first else { return "" }
        if grouping == .location { return container.storageLabel }
        return container.inventoryProduct?.name ?? container.productName ?? container.displayName
    }

    private func rows(_ containers: [StockContainer]) -> some View {
        ForEach(containers, id: \.objectID) { container in
            NavigationLink {
                StockContainerDetail(container: container)
            } label: {
                InventorySupplyRow(container: container, showLocation: grouping != .location)
            }
        }
    }
}

struct StockContainerDetail: View {
    @ObservedObject var container: StockContainer
    @State private var editingContainer = false
    @State private var adjustment: StockAdjustment?
    @State private var errorMessage: String?
    var showsProductLink = true

    var body: some View {
        List {
            Section {
                LabeledContent("Remaining", value: container.quantityLabel(container.remaining))
                StockLevelBar(container: container)
                if let product = container.productName {
                    LabeledContent("Product", value: product)
                }
                if let location = container.storageLocation {
                    LabeledContent("Storage Location", value: location)
                }
                if let expiresAt = container.expiresAt {
                    LabeledContent("Expiry") {
                        Text(expiresAt, format: .dateTime.year().month().day())
                    }
                }
                if container.lowThreshold > 0 {
                    LabeledContent("Low Stock At", value: container.quantityLabel(container.lowThreshold))
                }
                if container.needsReview {
                    Label("Check the physical count to resolve this balance.", systemImage: "exclamationmark.circle")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                }
            }

            if !container.isArchived {
                Section {
                    Button {
                        adjustment = .restock
                    } label: {
                        Label("Restock", systemImage: "plus.circle")
                    }
                    Button {
                        adjustment = .correction
                    } label: {
                        Label("Correct Count", systemImage: "equal.circle")
                    }
                    Button {
                        adjustment = .transfer
                    } label: {
                        Label("Transfer Stock", systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        adjustment = .discard
                    } label: {
                        Label("Record Disposal", systemImage: "minus.circle")
                    }
                }
            }

            if showsProductLink, let product = container.inventoryProduct {
                Section("Linked Product") {
                    NavigationLink {
                        ProductDetailScreen(product: product)
                    } label: {
                        Label(product.name, systemImage: "shippingbox")
                    }
                }
            }

            Section("History") {
                if container.stockChanges.isEmpty {
                    Text("No stock history").foregroundStyle(.secondary)
                }
                ForEach(container.stockChanges.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }, id: \.objectID) { change in
                    NavigationLink {
                        StockChangeDetail(change: change)
                    } label: {
                        LabeledContent {
                            Text(container.quantityLabel(change.balanceEffect)).monospacedDigit()
                        } label: {
                            Text(change.kindLabel)
                            if let date = change.date {
                                Text(date, format: .dateTime.year().month().day().hour().minute())
                            }
                        }
                    }
                }
            }
            Section {
                Button(container.isArchived ? "Unarchive Container" : "Archive Container", action: toggleArchived)
            } footer: {
                Text("Archived containers keep their balance and history.")
            }
        }
        .navigationTitle(container.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editingContainer = true }
            }
        }
        .sheet(isPresented: $editingContainer) {
            NavigationStack { StockContainerEditor(container: container) }
        }
        .sheet(item: $adjustment) { action in
            NavigationStack { StockAdjustmentEditor(container: container, action: action) }
        }
    }

    private func toggleArchived() {
        do {
            try PersistenceController.withJournalStoreWrite {
                let context = try PersistenceController.shared.journalEditContext()
                let record = try PersistenceController.journalObject(container, in: context)
                record.isArchived.toggle()
                try PersistenceController.saveJournalChanges(in: context)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t update this container."
        }
    }
}

private struct StockChangeDetail: View {
    @ObservedObject var change: StockChange

    var body: some View {
        List {
            Section {
                if let container = change.container {
                    if change.isReversedUse {
                        LabeledContent("Original Use", value: container.quantityLabel(-change.quantity))
                        LabeledContent("Returned", value: container.quantityLabel(-change.quantity))
                    } else {
                        LabeledContent("Quantity", value: container.quantityLabel(change.quantity))
                    }
                }
                if let date = change.date {
                    LabeledContent("Date") {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                if let note = change.note {
                    Text(note)
                }
            }
            let ingestions = (change.ingestions?.allObjects as? [Ingestion] ?? []).sorted()
            if !ingestions.isEmpty {
                Section {
                    ForEach(ingestions, id: \.objectID) { entry in
                        JournalEntryLink(ingestion: entry, timeFormat: .dateTime.month().day().hour().minute())
                    }
                } header: {
                    Text("Journal Entries")
                } footer: {
                    Text("If the physical amount used was different, correct the container’s count.")
                }
            }
        }
        .navigationTitle(change.kindLabel)
    }
}

struct StockContainerEditor: View {
    private enum ProductEditor: String, Identifiable {
        case customUnit, formulation

        var id: Self { self }
        var title: LocalizedStringKey { self == .customUnit ? "Custom Unit" : "Formulation" }
        var symbol: String { self == .customUnit ? "ruler" : "list.bullet" }
    }

    private enum ProductDraft {
        case customUnit(CustomUnitCodable)
        case formulation(FormulationCodable)

        var editor: ProductEditor {
            switch self {
            case .customUnit: .customUnit
            case .formulation: .formulation
            }
        }

        var name: String {
            switch self {
            case .customUnit(let draft): draft.name
            case .formulation(let draft): draft.name
            }
        }

        @MainActor var unit: String {
            switch self {
            case .customUnit(let draft): draft.unit
            case .formulation: Inventory.Use.formulationUnit
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    private var customUnits: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>

    let container: StockContainer?
    @State private var productID: NSManagedObjectID?
    @State private var importingPreset = false
    @State private var productDraft: ProductDraft?
    @State private var productEditor: ProductEditor?
    @State private var name: String
    @State private var productName: String
    @State private var location: String
    @State private var unit: String
    @State private var opening = ""
    @State private var capacity: String
    @State private var lowThreshold: String
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var errorMessage: String?

    init(container: StockContainer? = nil, initialProductID: NSManagedObjectID? = nil) {
        self.container = container
        _productID = State(initialValue: container?.customUnit?.objectID ?? container?.formulation?.objectID ?? initialProductID)
        _name = State(initialValue: container?.name ?? "")
        _productName = State(initialValue: container?.productName ?? "")
        _location = State(initialValue: container?.storageLocation ?? "")
        _unit = State(initialValue: container?.unit ?? "")
        _capacity = State(initialValue: container?.knownCapacity?.formatted(
            .number.grouping(.never).precision(.fractionLength(0...8))
        ) ?? "")
        let low = container?.lowThreshold ?? 0
        _lowThreshold = State(initialValue: low > 0 ? low.formatted(.number.grouping(.never).precision(.fractionLength(0...8))) : "")
        _hasExpiry = State(initialValue: container?.expiresAt != nil)
        _expiresAt = State(initialValue: container?.expiresAt ?? .now)
    }

    private var chosenCustomUnit: CustomUnit? { customUnits.first { $0.objectID == productID } }
    private var chosenFormulation: Formulation? { formulations.first { $0.objectID == productID } }

    private var chosenProductName: String? {
        chosenCustomUnit?.nameUnwrapped ?? chosenFormulation?.nameUnwrapped
            ?? productDraft?.name ?? productName.nonemptyTrimmed
    }

    private var containerName: String {
        name.nonemptyTrimmed ?? (container == nil ? chosenProductName ?? "" : "")
    }

    private var chosenUnit: String {
        if container != nil { return unit }
        if let chosenCustomUnit { return chosenCustomUnit.unitUnwrapped }
        if chosenFormulation != nil { return Inventory.Use.formulationUnit }
        if let productDraft { return productDraft.unit }
        if productID != nil { return "" }
        return unit.trimmed
    }

    var body: some View {
        Form {
            if container == nil {
                Section("Product") {
                    if let productDraft {
                        LabeledContent { Text(productDraft.name) } label: { Text(productDraft.editor.title) }
                        Button("Edit Product") { productEditor = productDraft.editor }
                        Button("Remove Draft", role: .destructive) { self.productDraft = nil }
                    } else {
                        if !customUnits.isEmpty || !formulations.isEmpty {
                            Picker("Linked Product", selection: $productID) {
                                Text("None").tag(Optional<NSManagedObjectID>.none)
                                ForEach(customUnits, id: \.objectID) { product in
                                    Text(product.nameUnwrapped).tag(Optional(product.objectID))
                                }
                                ForEach(formulations, id: \.objectID) { product in
                                    Text(product.nameUnwrapped).tag(Optional(product.objectID))
                                }
                            }
                        }
                        if productID == nil {
                            TextField("Product Name (Optional)", text: $productName)
                            PackageLabelDraftButton { productName = $0 }
                            Menu {
                                createProductButton(.customUnit)
                                createProductButton(.formulation)
                            } label: {
                                Label("Create Product", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            Button {
                                importingPreset = true
                            } label: {
                                Label("Import Preset", systemImage: "arrow.down.doc")
                            }
                        }
                    }
                }
            }
            Section("Container") {
                TextField("Name", text: $name, prompt: container == nil ? chosenProductName.map { Text($0) } : nil)
                TextField("Storage Location", text: $location)
                Toggle("Track Expiry", isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("Expiry", selection: $expiresAt, displayedComponents: .date)
                }
            }
            Section("Stock") {
                if container == nil {
                    if productID == nil, productDraft == nil {
                        TextField("Counting Unit", text: $unit)
                    } else {
                        LabeledContent("Counting Unit", value: chosenUnit)
                    }
                    TextField("Opening Quantity", text: $opening)
                        .keyboardType(.decimalPad)
                }
                TextField("Capacity (Optional)", text: $capacity)
                    .keyboardType(.decimalPad)
                TextField("Low-Stock Threshold (Optional)", text: $lowThreshold)
                    .keyboardType(.decimalPad)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                }
            }
        }
        .navigationTitle(container == nil ? "New Container" : "Edit Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(containerName.isEmpty || chosenUnit.isEmpty)
            }
        }
        .sheet(item: $productEditor) { editor in
            switch editor {
            case .customUnit:
                if case .customUnit(let draft) = productDraft {
                    NavigationStack {
                        FinishCustomUnitsScreen(
                            arguments: SubstanceAndRoute(
                                substance: AddIngestionSubstance(storedName: draft.substanceName, units: draft.originalUnit),
                                administrationRoute: draft.administrationRoute
                            ),
                            cancel: { productEditor = nil },
                            draft: draft
                        ) { edited in
                            productDraft = .customUnit(edited)
                            productEditor = nil
                        }
                    }
                } else {
                    CustomUnitsChooseSubstanceScreen(draftName: productName.trimmed) {
                        productDraft = .customUnit($0)
                    }
                }
            case .formulation:
                let draft: FormulationCodable = if case .formulation(let existing) = productDraft {
                    existing
                } else {
                    FormulationCodable(name: productName.trimmed, note: "", creationDate: .now, components: [])
                }
                EditFormulationScreen(draft: draft) { productDraft = .formulation($0) }
            }
        }
        .modifier(JournalPresetImporter(isPresented: $importingPreset) { importedProductID in
            productID = importedProductID
        })
    }

    private func createProductButton(_ editor: ProductEditor) -> some View {
        Button {
            productEditor = editor
        } label: {
            Label(editor.title, systemImage: editor.symbol)
        }
    }

    private func save() {
        guard !containerName.isEmpty, !chosenUnit.isEmpty else { return }
        let enteredCapacity = capacity.trimmed
        let knownCapacity = enteredCapacity.stockQuantity
        guard enteredCapacity.isEmpty || knownCapacity.map({ $0 > 0 }) == true else {
            errorMessage = "Enter a capacity greater than zero, or leave it blank."
            return
        }
        guard let initial = opening.isEmpty ? 0 : opening.stockQuantity,
              let threshold = lowThreshold.isEmpty ? 0 : lowThreshold.stockQuantity else {
            errorMessage = InventoryError.invalidQuantity.localizedDescription
            return
        }
        do {
            try PersistenceController.withJournalStoreWrite {
                let context = try PersistenceController.shared.journalEditContext()
                let record: StockContainer
                if let container {
                    record = try PersistenceController.journalObject(container, in: context)
                } else {
                    record = StockContainer(context: context)
                    record.customUnit = try chosenCustomUnit.map { try PersistenceController.journalObject($0, in: context) }
                    record.formulation = try chosenFormulation.map { try PersistenceController.journalObject($0, in: context) }
                    switch productDraft {
                    case .customUnit(let draft):
                        record.customUnit = draft.insert(into: context)
                    case .formulation(let draft):
                        record.formulation = draft.insert(into: context)
                    case nil:
                        break
                    }
                    record.productName = chosenProductName
                    record.unit = chosenUnit
                    try Inventory.stage(.opening, quantity: initial, in: record)
                }
                record.name = containerName
                record.storageLocation = location.nonemptyTrimmed
                record.capacity = knownCapacity.map(NSNumber.init(value:))
                record.lowThreshold = threshold
                record.expiresAt = hasExpiry ? expiresAt : nil
                try PersistenceController.saveJournalChanges(in: context)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t save this container."
        }
    }
}

enum StockAdjustment: String, Identifiable {
    case restock, correction, discard, transfer
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .restock: "Restock"
        case .correction: "Correct Count"
        case .discard: "Record Disposal"
        case .transfer: "Transfer Stock"
        }
    }
}

struct StockAdjustmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: StockContainer.allRequest())
    private var containers: FetchedResults<StockContainer>

    @ObservedObject var container: StockContainer
    let action: StockAdjustment
    @State private var quantity = ""
    @State private var note = ""
    @State private var destinationID: NSManagedObjectID?
    @State private var errorMessage: String?

    private var destinations: [StockContainer] {
        containers.filter { Inventory.canTransfer(from: container, to: $0) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current Count", value: container.quantityLabel(container.remaining))
                TextField(action == .correction ? "Physical Count" : "Quantity", text: $quantity)
                    .keyboardType(.decimalPad)
                if action == .transfer {
                    Picker("To", selection: $destinationID) {
                        Text("Choose Container").tag(Optional<NSManagedObjectID>.none)
                        ForEach(destinations, id: \.objectID) { destination in
                            Text(destination.displayName).tag(Optional(destination.objectID))
                        }
                    }
                    if destinations.isEmpty {
                        Text("Add another container for the same product and counting unit to transfer stock.")
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Note (Optional)", text: $note, axis: .vertical)
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.circle") }
            }
        }
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(quantity.isEmpty || (action == .transfer && destinationID == nil))
            }
        }
    }

    private func save() {
        guard let amount = quantity.stockQuantity, amount > 0 || action == .correction else {
            errorMessage = InventoryError.invalidQuantity.localizedDescription
            return
        }
        do {
            try PersistenceController.withJournalStoreWrite {
                let context = try PersistenceController.shared.journalEditContext()
                let record = try PersistenceController.journalObject(container, in: context)
                guard !record.isArchived else { throw InventoryError.sourceChanged }
                switch action {
                case .restock:
                    try Inventory.stage(.restock, quantity: amount, in: record, note: note.nonemptyTrimmed)
                case .correction:
                    guard record.remaining.isFinite else { throw InventoryError.invalidQuantity }
                    let difference = NSDecimalNumber(decimal: Decimal(amount) - Decimal(record.remaining)).doubleValue
                    try Inventory.stage(.correction, quantity: difference, in: record, note: note.nonemptyTrimmed)
                case .discard:
                    guard amount <= record.remaining else { throw InventoryError.insufficientStock }
                    try Inventory.stage(.discard, quantity: -amount, in: record, note: note.nonemptyTrimmed)
                case .transfer:
                    guard let destinationID, let destination = try context.existingObject(with: destinationID) as? StockContainer else {
                        throw InventoryError.incompatibleContainer
                    }
                    try Inventory.transfer(amount, from: record, to: destination, note: note.nonemptyTrimmed)
                }
                try PersistenceController.saveJournalChanges(in: context)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t update stock."
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonemptyTrimmed: String? { trimmed.isEmpty ? nil : trimmed }

    var stockQuantity: Double? {
        let parts = trimmed.components(separatedBy: Locale.current.decimalSeparator ?? ".")
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let value = try? Double(trimmed, format: .number, lenient: false), value.isFinite else { return nil }
        return value
    }
}
