import CoreData
import SwiftUI

struct StockLevelBar: View {
    @ObservedObject var container: StockContainer

    var body: some View {
        if let fraction = container.capacityFraction, let capacity = container.knownCapacity {
            ProgressView(value: fraction) {
                Text("Capacity")
            } currentValueLabel: {
                Text(container.quantityLabel(capacity))
            }
            .tint(container.isLow ? Color.orange : Color.accentColor)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityValue(Text("\(container.quantityLabel(container.remaining)) of \(container.quantityLabel(capacity))"))
        }
    }
}

struct InventorySupplyRow: View {
    @ObservedObject var container: StockContainer
    var showLocation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(container.quantityLabel(container.remaining)).monospacedDigit()
            } label: {
                Text(container.displayName)
                if showLocation, let location = container.storageLocation {
                    Text(location).foregroundStyle(.secondary)
                }
            }
            if container.needsReview {
                Text("Check Count")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if container.isExpired {
                Text("Past Expiry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if container.isLow {
                Text(container.remaining == 0 ? "Empty" : "Low Stock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            StockLevelBar(container: container)
        }
        .accessibilityElement(children: .combine)
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
                NavigationLink {
                    InventorySourceList(
                        matching: matching,
                        quantity: use.quantity,
                        selection: $selection
                    )
                } label: {
                    if let selected = matching.first(where: { $0.objectID == selection }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Draw From").font(.subheadline).foregroundStyle(.secondary)
                            InventorySupplyRow(container: selected)
                        }
                    } else {
                        LabeledContent("Draw From", value: selection == nil ? "No Container" : "Unavailable Container")
                    }
                }
            } header: {
                Text("Inventory")
            } footer: {
                if let selected = matching.first(where: { $0.objectID == selection }) {
                    if use.quantity <= selected.remaining {
                        Text("This log will draw \(selected.quantityLabel(use.quantity)) from this container.")
                    } else {
                        Text("Choose a container with at least \(selected.quantityLabel(use.quantity)), or log without drawing from inventory.")
                    }
                }
            }
        }
    }
}

private struct InventorySourceList: View {
    let matching: [StockContainer]
    let quantity: Double
    @Binding var selection: NSManagedObjectID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                choice(nil) {
                    Text("No Container")
                }
            }
            Section("Available Containers") {
                ForEach(matching, id: \.objectID) { container in
                    choice(container.objectID) {
                        InventorySupplyRow(container: container)
                    }
                    .disabled(container.needsReview || container.remaining < quantity)
                }
            }
        }
        .navigationTitle("Draw From")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice<Label: View>(
        _ id: NSManagedObjectID?, @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack {
                label()
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}
