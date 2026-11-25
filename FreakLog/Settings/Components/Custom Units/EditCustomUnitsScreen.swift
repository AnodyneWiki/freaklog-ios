import SwiftUI

struct EditCustomUnitsScreen: View {
    let customUnit: CustomUnit

    @State private var name: String = ""
    @State private var originalUnit = ""
    @State private var unit: String = ""
    @State private var unitPlural: String = ""
    @State private var note: String = ""
    @State private var dosePerUnit: Double?
    @State private var isEstimate: Bool = false
    @State private var estimatedDoseStandardDeviation: Double?
    @State private var isArchived: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        EditCustomUnitsScreenContent(
            substanceName: customUnit.substanceNameUnwrapped,
            administrationRoute: customUnit.administrationRouteUnwrapped,
            roaDose: customUnit.roaDose,
            name: $name,
            originalUnit: $originalUnit,
            unit: $unit,
            unitPlural: $unitPlural,
            note: $note,
            dosePerUnit: $dosePerUnit,
            isEstimate: $isEstimate,
            estimatedDoseStandardDeviation: $estimatedDoseStandardDeviation,
            isArchived: $isArchived,
            delete: delete,
            ingestionCount: customUnit.ingestionsUnwrapped.count,
            savedUnit: customUnit
        )
        .onAppear {
            name = customUnit.nameUnwrapped
            originalUnit = customUnit.originalUnitUnwrapped
            let pluralizableUnit = customUnit.pluralizableUnit
            unit = pluralizableUnit.singular
            unitPlural = pluralizableUnit.plural
            note = customUnit.noteUnwrapped
            dosePerUnit = customUnit.doseUnwrapped
            isEstimate = customUnit.isEstimate
            estimatedDoseStandardDeviation = customUnit.estimatedDoseStandardDeviationUnwrapped
            isArchived = customUnit.isArchived
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
    }

    private func save() {
        customUnit.name = name
        customUnit.originalUnit = originalUnit
        customUnit.unit = unit
        customUnit.unitPlural = unitPlural
        customUnit.note = note
        customUnit.dose = dosePerUnit ?? 0
        customUnit.isEstimate = isEstimate
        customUnit.estimatedDoseStandardDeviation = estimatedDoseStandardDeviation ?? 0
        customUnit.isArchived = isArchived
        PersistenceController.shared.saveViewContext()
        dismiss()
    }

    private func delete() {
        Task {
            if await IngestionDeletion.delete(customUnit: customUnit) {
                dismiss()
            }
        }
    }
}

struct EditCustomUnitsScreenContent: View {
    let substanceName: String
    let administrationRoute: AdministrationRoute
    let roaDose: RoaDose?
    @Binding var name: String
    @Binding var originalUnit: String
    @Binding var unit: String
    @Binding var unitPlural: String
    @Binding var note: String
    @Binding var dosePerUnit: Double?
    @Binding var isEstimate: Bool
    @Binding var estimatedDoseStandardDeviation: Double?
    @Binding var isArchived: Bool
    let delete: () -> Void
    let ingestionCount: Int
    var savedUnit: CustomUnit?

    @State private var isDeleteShown = false

    var body: some View {
        Form {
            Section {
                if ingestionCount > 0 {
                    let pluralizableUnit = PluralizableUnit(singular: "ingestion", plural: "ingestions")
                    Text("\(ingestionCount.with(pluralizableUnit: pluralizableUnit)) are affected by this edit")
                } else {
                    Text("No ingestions are using this unit yet")
                }
            }
            Section {
                LabeledContent {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                } label: {
                    Text("Name:")
                }
                LabeledContent {
                    TextField("Unit", text: $unit)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("Unit singular:")
                }
                LabeledContent {
                    TextField("Unit plural", text: $unitPlural)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("Unit plural:")
                }
                TextField("Enter Note", text: $note)
                    .autocapitalization(.sentences)
            }
            Section {
                if let roaDose {
                    RoaDoseRow(roaDose: roaDose)
                }
                DosePicker(
                    roaDose: roaDose,
                    doseMaybe: $dosePerUnit,
                    selectedUnits: $originalUnit
                )
                EstimateFields(
                    isEstimate: $isEstimate,
                    standardDeviation: $estimatedDoseStandardDeviation,
                    units: originalUnit,
                    mean: dosePerUnit
                )
            }.listRowSeparator(.hidden)

            if let originalUnit = roaDose?.units, !unit.isEmpty {
                Section("Ingestion Preview") {
                    IngestionRowPreview(
                        substanceName: substanceName,
                        administrationRoute: administrationRoute,
                        isEstimate: isEstimate,
                        unit: unit,
                        unitPlural: unitPlural,
                        dosePerUnit: dosePerUnit,
                        dosePerUnitStandardDeviation: estimatedDoseStandardDeviation,
                        originalUnit: originalUnit,
                        name: name)
                }
            }

            Section {
                Toggle("Archive", isOn: $isArchived).tint(.accentColor)
            } footer: {
                Text("Archived custom units don't show up when adding ingestions")
            }

            if let savedUnit {
                Section {
                    JournalPresetShareLink(product: .customUnit(savedUnit), title: "Share Saved Preset")
                }
            }

            Section {
                Button {
                    if ingestionCount > 0 {
                        isDeleteShown.toggle()
                    } else {
                        delete()
                    }
                } label: {
                    Label("Delete Unit", systemImage: "trash").foregroundColor(.red)
                }
            }
        }
        .alert("Are you sure?", isPresented: $isDeleteShown, actions: {
            Button(role: .destructive) {
                delete()
            } label: {
                Text("Delete")
            }
            Button(role: .cancel) {

            } label: {
                Text("Cancel")
            }
        }, message: {
            Text("Deleting this unit will delete \(ingestionCount.with(pluralizableUnit: PluralizableUnit(singular: "ingestion", plural: "ingestions"))) that are using it. If you don't want to use it anymore archive it instead.")
        })
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Unit")
    }

}

#Preview {
    NavigationStack {
        EditCustomUnitsScreenContent(
            substanceName: "MDMA",
            administrationRoute: .oral,
            roaDose: SubstanceRepo.shared.getSubstance(name: "MDMA")!.getDose(for: .oral)!,
            name: .constant("pink rocket"),
            originalUnit: .constant("mg"),
            unit: .constant("pill"),
            unitPlural: .constant("pills"),
            note: .constant("These are my notes"),
            dosePerUnit: .constant(50),
            isEstimate: .constant(false),
            estimatedDoseStandardDeviation: .constant(nil),
            isArchived: .constant(false),
            delete: {},
            ingestionCount: 4
        )
    }
}
