import SwiftUI

struct AddSprayScreen: View {
    @State private var name = ""
    @State private var volumeText = ""
    @State private var countText = ""
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    private var volume: Double? { SprayCalculation.positiveNumber(volumeText) }
    private var count: Double? { SprayCalculation.positiveNumber(countText) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section {
                    LabeledContent("Bottle Volume") {
                        TextField("Volume", text: $volumeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Bottle volume in milliliters")
                        Text("mL").foregroundStyle(.secondary)
                    }
                    LabeledContent("Number of Sprays") {
                        TextField("Count", text: $countText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Number of sprays")
                    }
                } header: {
                    Text("Calibration")
                } footer: {
                    if (!volumeText.isEmpty && volume == nil) || (!countText.isEmpty && count == nil) {
                        Text("Enter a volume and spray count greater than zero.")
                    } else {
                        Text("Use the measured volume and the number of sprays it produces.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Spray")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || volume == nil || count == nil)
                }
            }
            .alert("Couldn’t Save Spray", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, let volume, let count else { return }
        do {
            try PersistenceController.withJournalStoreWrite {
                let context = try PersistenceController.shared.journalEditContext()
                for existing in try context.fetch(PersistenceController.sprayRequest()) where existing.isPreferred {
                    existing.isPreferred = false
                }
                let spray = Spray(context: context)
                spray.creationDate = .now
                spray.name = trimmedName
                spray.contentInMl = volume
                spray.numSprays = count
                spray.isPreferred = true
                try context.save()
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    AddSprayScreen()
}
