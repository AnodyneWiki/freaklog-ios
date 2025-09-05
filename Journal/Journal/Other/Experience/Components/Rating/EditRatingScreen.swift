import SwiftUI

struct EditRatingScreen: View {
    @ObservedObject var rating: ShulginRating
    @Binding var isHidden: Bool

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
    }

    func save() {
        rating.time = selectedTime
        rating.option = selectedRating.rawValue
        rating.experience?.objectWillChange.send()
        PersistenceController.shared.saveViewContext()
    }

    func delete() {
        PersistenceController.shared.viewContext.delete(rating)
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}
