import CoreData
import SwiftUI

struct InventoryScreen: View {
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
                    let groups = Dictionary(grouping: active) {
                        grouping == .location ? $0.storageLabel : ($0.productName ?? $0.displayName)
                    }
                    ForEach(groups.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }), id: \.self) { title in
                        Section(header: Text(title)) {
                            rows(groups[title] ?? [])
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

    private func rows(_ containers: [StockContainer]) -> some View {
        ForEach(containers, id: \.objectID) { container in
            NavigationLink {
                StockContainerDetail(container: container)
            } label: {
                StockContainerRow(container: container, showLocation: grouping != .location)
            }
        }
    }
}

private struct StockContainerRow: View {
    @ObservedObject var container: StockContainer
    let showLocation: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(container.displayName)
                if showLocation, let location = container.storageLocation {
                    Text(location).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(container.quantityLabel(container.remaining)).monospacedDigit()
                if container.needsReview {
                    Text("Check count")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if container.isExpired {
                    Text("Past expiry")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if container.isLow {
                    Text(container.remaining == 0 ? "Empty" : "Low stock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension StockContainer {
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Calendar.current.compare(expiresAt, to: .now, toGranularity: .day) == .orderedAscending
    }
}

struct StockContainerDetail: View {
    @ObservedObject var container: StockContainer
    @State private var editingContainer = false
    @State private var adjustment: StockAdjustment?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Remaining", value: container.quantityLabel(container.remaining))
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

private struct StockContainerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: PersistenceController.activeCustomUnitsRequest())
    private var customUnits: FetchedResults<CustomUnit>
    @FetchRequest(fetchRequest: PersistenceController.formulationsRequest())
    private var formulations: FetchedResults<Formulation>

    let container: StockContainer?
    @State private var productID: NSManagedObjectID?
    @State private var name: String
    @State private var productName: String
    @State private var location: String
    @State private var unit: String
    @State private var opening = ""
    @State private var lowThreshold: String
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var errorMessage: String?

    init(container: StockContainer? = nil) {
        self.container = container
        _productID = State(initialValue: container?.customUnit?.objectID ?? container?.formulation?.objectID)
        _name = State(initialValue: container?.name ?? "")
        _productName = State(initialValue: container?.productName ?? "")
        _location = State(initialValue: container?.storageLocation ?? "")
        _unit = State(initialValue: container?.unit ?? "")
        let low = container?.lowThreshold ?? 0
        _lowThreshold = State(initialValue: low > 0 ? low.formatted(.number.grouping(.never).precision(.fractionLength(0...8))) : "")
        _hasExpiry = State(initialValue: container?.expiresAt != nil)
        _expiresAt = State(initialValue: container?.expiresAt ?? .now)
    }

    private var chosenCustomUnit: CustomUnit? { customUnits.first { $0.objectID == productID } }
    private var chosenFormulation: Formulation? { formulations.first { $0.objectID == productID } }

    private var chosenUnit: String {
        if container != nil { return unit }
        if let chosenCustomUnit { return chosenCustomUnit.unitUnwrapped }
        if chosenFormulation != nil { return Inventory.Use.formulationUnit }
        return unit.trimmed
    }

    var body: some View {
        Form {
            Section("Container") {
                TextField("Name", text: $name)
                TextField("Storage Location", text: $location)
                Toggle("Track Expiry", isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("Expiry", selection: $expiresAt, displayedComponents: .date)
                }
            }
            if container == nil {
                Section("Product") {
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
                        TextField("Counting Unit", text: $unit)
                    } else {
                        LabeledContent("Counting Unit", value: chosenUnit)
                    }
                }
            }
            Section("Stock") {
                if container == nil {
                    TextField("Opening Quantity", text: $opening)
                        .keyboardType(.decimalPad)
                }
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
                Button("Save", action: save).disabled(name.trimmed.isEmpty || chosenUnit.isEmpty)
            }
        }
    }

    private func save() {
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
                    record.productName = chosenCustomUnit?.nameUnwrapped ?? chosenFormulation?.nameUnwrapped ?? productName.nonemptyTrimmed
                    record.unit = chosenUnit
                    try Inventory.stage(.opening, quantity: initial, in: record)
                }
                record.name = name.trimmed
                record.storageLocation = location.nonemptyTrimmed
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

private enum StockAdjustment: String, Identifiable {
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

private struct StockAdjustmentEditor: View {
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

struct InventorySourcePicker: View {
    let use: Inventory.Use
    @Binding var selection: NSManagedObjectID?
    @FetchRequest(fetchRequest: StockContainer.allRequest())
    private var containers: FetchedResults<StockContainer>

    private var matching: [StockContainer] {
        containers.filter(use.matches)
    }

    var body: some View {
        if !matching.isEmpty || selection != nil {
            Section {
                Picker("Draw From", selection: $selection) {
                    Text("None").tag(Optional<NSManagedObjectID>.none)
                    ForEach(matching, id: \.objectID) { container in
                        Text("\(container.displayName) · \(container.quantityLabel(container.remaining))")
                            .tag(Optional(container.objectID))
                    }
                    if let selection, !matching.contains(where: { $0.objectID == selection }) {
                        Text("Unavailable Container").tag(Optional(selection))
                    }
                }
            } header: {
                Text("Inventory")
            } footer: {
                if let container = matching.first(where: { $0.objectID == selection }) {
                    Text("This log will draw \(container.quantityLabel(use.quantity)) from this container.")
                }
            }
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
