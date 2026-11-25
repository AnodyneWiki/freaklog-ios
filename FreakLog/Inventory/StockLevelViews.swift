import CoreData
import SwiftUI

struct StockLevelBar: View {
    @ObservedObject var container: StockContainer

    var body: some View {
        if let fraction = container.capacityFraction {
            ProgressView(value: fraction)
                .tint(container.isLow ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
        }
    }
}

extension StockContainer {
    var stockBalanceLabel: String {
        guard capacityFraction != nil, let capacity = knownCapacity else { return quantityLabel(remaining) }
        let amount = remaining.formatted(.number.precision(.fractionLength(0...8)))
        return String(localized: "\(amount) of \(quantityLabel(capacity))")
    }
}

struct InventorySupplyRow: View {
    @ObservedObject var container: StockContainer
    var showLocation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(container.stockBalanceLabel).monospacedDigit()
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
    @State private var attachedReport: (containerID: NSManagedObjectID, report: InventoryLabReport)?
    @State private var preview: InventoryLabReport?

    private var matching: [StockContainer] {
        containers.filter(use.matches)
    }

    var body: some View {
        let matchingContainers = matching
        let selected = matchingContainers.first { $0.objectID == selection }
        if !matchingContainers.isEmpty || selection != nil {
            Section {
                NavigationLink {
                    InventorySourceList(
                        matching: matchingContainers,
                        quantity: use.quantity,
                        selection: $selection
                    )
                } label: {
                    if let selected {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Draw From").font(.subheadline).foregroundStyle(.secondary)
                            InventorySupplyRow(container: selected)
                        }
                    } else {
                        LabeledContent("Draw From", value: selection == nil ? "No Container" : "Unavailable Container")
                    }
                }
                .task(id: selected?.objectID) {
                    attachedReport = nil
                    guard let selected else { return }
                    let id = selected.objectID
                    let loaded = try? await InventoryLabReportStore.load(for: selected.labReportContainerID)
                    if let loaded, !Task.isCancelled { attachedReport = (id, loaded) }
                }
                if let selected, let attachedReport, attachedReport.containerID == selected.objectID,
                   attachedReport.report.stockFingerprint == selected.labReportStockFingerprint {
                    Button {
                        preview = attachedReport.report
                    } label: {
                        InventoryLabReportLabel(filename: attachedReport.report.filename)
                    }
                    .sheet(item: $preview) { report in InventoryLabReportPreview(report: report) }
                }
            } header: {
                Text("Inventory")
            } footer: {
                if let selected {
                    if selected.needsReview {
                        Text("Check the count for this container or choose a different one.")
                    } else if use.quantity <= selected.remaining {
                        Text("This log will draw \(selected.quantityLabel(use.quantity)) from this container.")
                        if selected.isExpired, let expiry = selected.expiresAt {
                            Label("Past recorded expiry of \(expiry.formatted(date: .abbreviated, time: .omitted)).",
                                  systemImage: "calendar.badge.exclamationmark")
                        }
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

    private func canDraw(from container: StockContainer) -> Bool {
        !container.needsReview && container.remaining >= quantity
    }

    var body: some View {
        List {
            Section {
                choice(nil) {
                    Text("No Container")
                }
            }
            Section("Available Containers") {
                let available = matching.filter(canDraw)
                if available.isEmpty {
                    Text("No containers can supply this amount.").foregroundStyle(.secondary)
                }
                ForEach(available, id: \.objectID) { container in
                    choice(container.objectID) {
                        InventorySupplyRow(container: container)
                    }
                }
            }
            let unavailable = matching.filter { !canDraw(from: $0) }
            if !unavailable.isEmpty {
                Section("Unavailable Containers") {
                    ForEach(unavailable, id: \.objectID) { container in
                        VStack(alignment: .leading, spacing: 4) {
                            InventorySupplyRow(container: container)
                            if !container.needsReview {
                                Text("\(container.quantityLabel(quantity)) needed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}
