import CoreData
import Foundation

enum StockChangeKind: String {
    case opening, restock, correction, discard, use, batchUse, reversedUse, transferIn, transferOut

    var title: String {
        switch self {
        case .opening: String(localized: "Opening count")
        case .restock: String(localized: "Restock")
        case .correction: String(localized: "Count correction")
        case .discard: String(localized: "Discard")
        case .use, .batchUse: String(localized: "Used")
        case .reversedUse: String(localized: "Usage Reversed")
        case .transferIn: String(localized: "Transfer in")
        case .transferOut: String(localized: "Transfer out")
        }
    }
}

enum InventoryError: LocalizedError {
    case invalidQuantity, insufficientStock, sourceChanged, incompatibleContainer, cannotReverseUse

    var errorDescription: String? {
        switch self {
        case .invalidQuantity: "Enter a valid quantity."
        case .insufficientStock: "This container has less stock than the amount entered. Check its count or choose another container."
        case .sourceChanged: "The selected container or product has changed. Choose a container again."
        case .incompatibleContainer: "Choose a different container for the same product and unit."
        case .cannotReverseUse: "Stock couldn’t be returned for this entry. Check the container’s history."
        }
    }
}

extension StockContainer {
    static func allRequest() -> NSFetchRequest<StockContainer> {
        let request = NSFetchRequest<StockContainer>(entityName: "StockContainer")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \StockContainer.name, ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = ["customUnit", "formulation", "changes"]
        return request
    }

    var displayName: String {
        name ?? String(localized: "Container")
    }

    var storageLabel: String {
        storageLocation ?? String(localized: "No Location")
    }

    var stockChanges: [StockChange] {
        changes?.allObjects as? [StockChange] ?? []
    }

    var remaining: Double {
        let total = stockChanges.reduce(Decimal.zero) { balance, change in
            guard change.quantity.isFinite else { return balance }
            return balance + Decimal(change.balanceEffect)
        }
        return NSDecimalNumber(decimal: total).doubleValue
    }

    func quantityLabel(_ amount: Double) -> String {
        guard amount.isFinite else { return String(localized: "Unavailable") }
        return [amount.formatted(.number.precision(.fractionLength(0...8))), unit ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var needsReview: Bool {
        !remaining.isFinite || remaining < 0 || stockChanges.contains { !$0.quantity.isFinite }
    }

    var isLow: Bool {
        guard !needsReview else { return false }
        return remaining == 0 || (lowThreshold > 0 && remaining <= lowThreshold)
    }
}

extension StockChange {
    var isReversedUse: Bool { kind == StockChangeKind.reversedUse.rawValue }

    var balanceEffect: Double { isReversedUse ? 0 : quantity }

    var canReverseUse: Bool {
        kind == StockChangeKind.use.rawValue
            && ingestions?.count == 1
            && container != nil
            && quantity.isFinite
            && quantity < 0
    }

    var kindLabel: String {
        kind.flatMap(StockChangeKind.init(rawValue:))?.title ?? String(localized: "Stock change")
    }
}

@MainActor
enum Inventory {
    static func stageUsageReversal(for ingestion: Ingestion) throws {
        guard let change = ingestion.stockChange, change.canReverseUse else {
            throw InventoryError.cannotReverseUse
        }
        change.kind = StockChangeKind.reversedUse.rawValue
    }

    static func stage(
        _ kind: StockChangeKind, quantity: Double, in container: StockContainer,
        at date: Date = .now, note: String? = nil, linkedIngestions: [Ingestion] = []
    ) throws {
        guard quantity.isFinite, !Decimal(quantity).isNaN,
              let context = container.managedObjectContext, !container.isDeleted else {
            throw InventoryError.invalidQuantity
        }
        guard quantity != 0 || kind == .opening else { return }
        let change = StockChange(context: context)
        change.kind = kind.rawValue
        change.quantity = quantity
        change.date = date
        change.note = note
        change.container = container
        linkedIngestions.forEach { $0.stockChange = change }
    }

    static func transfer(
        _ quantity: Double, from source: StockContainer, to destination: StockContainer,
        note: String?
    ) throws {
        guard quantity.isFinite, quantity > 0 else { throw InventoryError.invalidQuantity }
        guard canTransfer(from: source, to: destination) else { throw InventoryError.incompatibleContainer }
        guard quantity <= source.remaining else { throw InventoryError.insufficientStock }
        let date = Date.now
        let toLabel = String(localized: "To \(destination.displayName)")
        let fromLabel = String(localized: "From \(source.displayName)")
        try stage(.transferOut, quantity: -quantity, in: source, at: date, note: [toLabel, note].compactMap { $0 }.joined(separator: "\n"))
        try stage(.transferIn, quantity: quantity, in: destination, at: date, note: [fromLabel, note].compactMap { $0 }.joined(separator: "\n"))
    }

    static func canTransfer(from source: StockContainer, to destination: StockContainer) -> Bool {
        guard source.objectID != destination.objectID, !source.isArchived, !destination.isArchived,
              source.unit == destination.unit, source.customUnit == destination.customUnit,
              source.formulation == destination.formulation else { return false }
        if source.customUnit == nil, source.formulation == nil {
            return source.productName == destination.productName
                && source.productName != nil
        }
        return true
    }

    @MainActor
    struct Use {
        let productID: NSManagedObjectID
        let unit: String
        let quantity: Double
        let isFormulation: Bool

        init?(_ arguments: [FinishIngestionScreenArguments]) {
            guard let first = arguments.first else { return nil }
            if let product = first.formulation, let quantity = first.formulationAmount,
               quantity.isFinite, quantity > 0,
               arguments.allSatisfy({ $0.formulation == product && $0.formulationAmount == quantity }) {
                self.productID = product.objectID
                self.unit = Self.formulationUnit
                self.quantity = quantity
                self.isFormulation = true
            } else if arguments.count == 1, let product = first.customUnit,
                      let quantity = first.dose, quantity.isFinite, quantity > 0,
                      !product.unitUnwrapped.isEmpty {
                self.productID = product.objectID
                self.unit = product.unitUnwrapped
                self.quantity = quantity
                self.isFormulation = false
            } else {
                return nil
            }
        }

        static var formulationUnit: String { "servings" }

        func matches(_ container: StockContainer) -> Bool {
            let product = isFormulation ? container.formulation?.objectID : container.customUnit?.objectID
            return !container.isArchived && container.unit == unit && product == productID
        }

        func stage(
            using containerID: NSManagedObjectID, for ingestions: [Ingestion],
            at date: Date, in context: NSManagedObjectContext
        ) throws {
            guard let container = try context.existingObject(with: containerID) as? StockContainer,
                  matches(container) else { throw InventoryError.sourceChanged }
            guard quantity <= container.remaining else { throw InventoryError.insufficientStock }
            let kind: StockChangeKind = ingestions.count == 1 ? .use : .batchUse
            try Inventory.stage(kind, quantity: -quantity, in: container, at: date, linkedIngestions: ingestions)
        }
    }
}
