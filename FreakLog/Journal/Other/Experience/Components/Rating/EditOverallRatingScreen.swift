import SwiftUI

struct EditOverallRatingScreen: View {
    @ObservedObject var rating: ShulginRating
    @Environment(\.dismiss) var dismiss
    @State private var selectedRating = ShulginRatingOption.twoPlus

    var body: some View {
        List {
            SelectRatingSection(selectedRating: $selectedRating)
            RatingExplanationSection()
            Button(action: delete) {
                Label("Delete Rating", systemImage: "trash").foregroundColor(.red)
            }
        }.onAppear {
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
    }

    func save() {
        rating.option = selectedRating.rawValue
        PersistenceController.shared.saveViewContext()
    }

    func delete() {
        PersistenceController.shared.viewContext.delete(rating)
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}
