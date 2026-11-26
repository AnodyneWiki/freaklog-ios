import SwiftUI

struct EditRatingScreen: View {
    @ObservedObject var rating: ShulginRating
    @State private var isHidden = false
    @State private var showsSaveError = false

    @Environment(\.dismiss) var dismiss
    @State private var selectedTime = Date.now
    @State private var selectedRating = ShulginRatingOption.twoPlus

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Time",
                    selection: $selectedTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
            SelectRatingSection(selectedRating: $selectedRating)
            RatingExplanationSection()
            Section {
                Toggle("Hide in timeline", isOn: $isHidden).tint(.accentColor)
                Button(action: delete) {
                    Label("Delete Rating", systemImage: "trash").foregroundColor(.red)
                }
            }
        }.onAppear {
            selectedTime = rating.timeUnwrapped
            selectedRating = rating.optionUnwrapped
            isHidden = rating.isHiddenInTimeline
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
        .navigationTitle("Edit Rating")
        .alert("Couldn’t Save the Rating", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        }
    }

    func save() {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let editable = try PersistenceController.journalObject(rating, in: context)
            editable.time = selectedTime
            editable.option = selectedRating.rawValue
            editable.isHiddenInTimeline = isHidden
            try context.save()
            dismiss()
        } catch {
            showsSaveError = true
        }
    }

    func delete() {
        PersistenceController.shared.viewContext.delete(rating)
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}
