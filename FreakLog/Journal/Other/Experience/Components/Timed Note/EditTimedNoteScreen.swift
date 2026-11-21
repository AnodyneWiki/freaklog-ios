import SwiftUI

struct EditTimedNoteScreen: View {
    @ObservedObject var timedNote: TimedNote
    @ObservedObject var experience: Experience

    @Environment(\.dismiss) private var dismiss
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
        timedNote.time = time
        timedNote.note = note
        timedNote.colorAsText = color.rawValue
        timedNote.isPartOfTimeline = isPartOfTimeline
        timedNote.experience?.objectWillChange.send()
        PersistenceController.shared.saveViewContext()
    }

    func delete() {
        PersistenceController.shared.viewContext.delete(timedNote)
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}
