import SwiftUI

struct AddRatingScreen: View {
    let experience: Experience
    let canDefineOverall: Bool
    @Environment(\.dismiss) var dismiss
    @State private var selectedTime = Date.now
    @State private var selectedRating = ShulginRatingOption.twoPlus
    @State private var isOverallRating = false
    @State private var showsSaveError = false
    @EnvironmentObject private var toastViewModel: ToastViewModel

    var body: some View {
        NavigationStack {
            screen.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    doneButton
                }
            }
        }
        .onFirstAppear {
            if experience.isCurrent {
                selectedTime = Date()
            } else {
                selectedTime = experience.sortDateUnwrapped.addingTimeInterval(30 * 60)
            }
        }
        .alert("Rating Couldn’t Be Saved", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your rating is still here. Try saving again.")
        }
    }

    var doneButton: some View {
        DoneButton {
            do {
                try save()
                toastViewModel.showSuccessToast(message: "Rating Added")
                dismiss()
            } catch {
                showsSaveError = true
            }
        }
    }

    var screen: some View {
        RatingScreenContent(
            selectedTime: $selectedTime,
            selectedRating: $selectedRating,
            canDefineOverall: canDefineOverall,
            isOverallRating: $isOverallRating
        )
        .navigationTitle("Add Shulgin Rating")
    }

    private func save() throws {
        try PersistenceController.withJournalStoreWrite {
            let context = try PersistenceController.shared.journalEditContext()
            let storedExperience = try PersistenceController.journalObject(experience, in: context)
            let newRating = ShulginRating(context: context)
            newRating.creationDate = .now
            newRating.time = canDefineOverall && isOverallRating ? nil : selectedTime
            newRating.option = selectedRating.rawValue
            newRating.experience = storedExperience
            try PersistenceController.saveJournalChanges(in: context)
        }
    }
}
