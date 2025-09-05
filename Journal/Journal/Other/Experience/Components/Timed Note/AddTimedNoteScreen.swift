import SwiftUI

struct AddTimedNoteScreen: View {
    let experience: Experience

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date.now
    @State private var note = ""
    @State private var color = SubstanceColor.blue
    @State private var isPartOfTimeline = false
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @FocusState private var isTextFieldFocused: Bool
    @State private var alreadyUsedColors: [SubstanceColor] = []
    @State private var otherColors: [SubstanceColor] = []

    var body: some View {
        NavigationStack {
            TimedNoteScreenContent(
                time: $time,
                note: $note,
                color: $color,
                isPartOfTimeline: $isPartOfTimeline,
                isTextFieldFocused: $isTextFieldFocused,
                alreadyUsedColors: alreadyUsedColors,
                otherColors: otherColors
            )
            .navigationTitle("Add Timed Note")
            .toolbar {
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
        .onAppear {
            isTextFieldFocused = true
            isPartOfTimeline = experience.isCurrent
            alreadyUsedColors = Array(Set(experience.timedNotesForTimeline.map { $0.color })).sorted()
            otherColors = Array(Set(SubstanceColor.allCases).subtracting(alreadyUsedColors)).sorted()
            if let otherColor = otherColors.randomElement() {
                color = otherColor
            }
        }
    }

    var doneButton: some View {
        DoneButton {
            save()
            toastViewModel.showSuccessToast(message: "Note Added")
            dismiss()
        }
    }

    func save() {
        let context = PersistenceController.shared.viewContext
        let newNote = TimedNote(context: context)
        newNote.creationDate = Date()
        newNote.time = time
        newNote.note = note
        newNote.colorAsText = color.rawValue
        newNote.isPartOfTimeline = isPartOfTimeline
        newNote.experience = experience
        try? context.save()
    }
}
