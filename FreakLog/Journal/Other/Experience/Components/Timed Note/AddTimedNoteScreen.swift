import SwiftUI

// Adds a note to the experience, or without one to the experience a new ingestion at the note's time
// would join, starting a new experience if there is none
struct AddTimedNoteScreen: View {
    let experience: Experience?

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date.now
    @State private var note = ""
    @State private var color = SubstanceColor.blue
    @State private var isPartOfTimeline = false
    @State private var usedColors: [SubstanceColor] = []
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @FocusState private var isTextFieldFocused: Bool

    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest())
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    var body: some View {
        NavigationStack {
            TimedNoteScreenContent(
                time: $time,
                note: $note,
                color: $color,
                isPartOfTimeline: $isPartOfTimeline,
                isTextFieldFocused: $isTextFieldFocused,
                usedColors: usedColors,
                isShowingWebhookToggle: !enabledWebhookPresets.isEmpty
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
            let experience = targetExperience(at: time)
            isPartOfTimeline = experience?.isCurrent ?? true
            usedColors = experience?.timedNotesForTimeline.map(\.color) ?? []
            if let otherColor = SubstanceColor.unused(avoiding: usedColors).randomElement() {
                color = otherColor
            }
        }
    }

    private func targetExperience(at time: Date) -> Experience? {
        experience ?? ExperienceLogic.closestExperience(from: PersistenceController.shared.getExperiences(near: time), to: time)
    }

    var doneButton: some View {
        DoneButton {
            do {
                try save()
                toastViewModel.showSuccessToast(message: "Note Added")
            } catch {
                toastViewModel.showErrorToast(message: "Failed to add note")
            }
            dismiss()
        }
    }

    func save() throws {
        let context = PersistenceController.shared.viewContext
        let newNote = TimedNote(context: context)
        newNote.creationDate = Date()
        newNote.time = time
        newNote.note = note
        newNote.colorAsText = color.rawValue
        newNote.isPartOfTimeline = isPartOfTimeline
        newNote.experience = targetExperience(at: time) ?? Experience.create(at: time, in: context)
        try TimedNoteSaving.save(newNote, sendingWebhooksTo: WebhookPreset.defaultPresetObjectIDs())
    }
}
