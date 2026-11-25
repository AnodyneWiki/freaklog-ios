import SwiftUI

struct EditTimedNoteScreen: View {
    @ObservedObject var timedNote: TimedNote
    @ObservedObject var experience: Experience

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @State private var time = Date.now
    @State private var note = ""
    @State private var color = SubstanceColor.blue
    @State private var isPartOfTimeline = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            TimedNoteScreenContent(
                time: $time,
                note: $note,
                color: $color,
                isPartOfTimeline: $isPartOfTimeline,
                isTextFieldFocused: $isTextFieldFocused,
                usedColors: experience.timedNotesForTimeline.map(\.color)
            )
            .onFirstAppear { // needed because else state is reset when navigating back from color picker
                time = timedNote.timeUnwrapped
                note = timedNote.noteUnwrapped
                color = timedNote.color
                isPartOfTimeline = timedNote.isPartOfTimeline
            }
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(action: delete) {
                        Label("Delete Note", systemImage: "trash")
                    }
                }
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
            .navigationTitle("Edit Note")
        }
    }

    func save() {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let updated = try PersistenceController.journalObject(timedNote, in: context)
            updated.time = time
            updated.note = note
            updated.colorAsText = color.rawValue
            updated.isPartOfTimeline = isPartOfTimeline
            try TimedNoteSaving.save(updated)
            experience.objectWillChange.send()
            dismiss()
        } catch {
            toastViewModel.showErrorToast(message: "Failed to save note")
        }
    }

    func delete() {
        Task {
            if await IngestionDeletion.delete(timedNote: timedNote) {
                dismiss()
            } else {
                toastViewModel.showErrorToast(message: "Failed to delete note")
            }
        }
    }
}
