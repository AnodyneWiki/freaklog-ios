import CoreData
import SwiftUI

// Adds a note to the experience, or without one to the experience a new ingestion at the note's time
// would join, starting a new experience if there is none
struct AddTimedNoteScreen: View {
    let experience: Experience?
    private let startsOnTimeline: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var note = ""
    @State private var details = TimedNoteDetails()
    @State private var color = SubstanceColor.blue
    @State private var isPartOfTimeline = false
    @State private var usedColors: [SubstanceColor] = []
    @EnvironmentObject private var toastViewModel: ToastViewModel
    @FocusState private var isTextFieldFocused: Bool

    @FetchRequest(fetchRequest: PersistenceController.enabledWebhookPresetsRequest())
    private var enabledWebhookPresets: FetchedResults<WebhookPreset>

    init(experience: Experience?, initialTime: Date? = nil) {
        self.experience = experience
        startsOnTimeline = initialTime != nil
        _time = State(initialValue: initialTime ?? .now)
    }

    var body: some View {
        NavigationStack {
            TimedNoteScreenContent(
                time: $time,
                note: $note,
                details: $details,
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
            isPartOfTimeline = startsOnTimeline || (experience?.isCurrent ?? true)
            usedColors = experience?.timedNotesForTimeline.map(\.color) ?? []
            color = SubstanceColor.suggested(avoiding: usedColors)
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
                dismiss()
            } catch {
                toastViewModel.showErrorToast(message: "Failed to add note")
            }
        }
    }

    func save() throws {
        let context = try PersistenceController.shared.journalEditContext()
        let newNote = TimedNote(context: context)
        newNote.creationDate = Date()
        newNote.time = time
        newNote.note = note
        newNote.details = details
        newNote.colorAsText = color.rawValue
        newNote.isPartOfTimeline = isPartOfTimeline
        newNote.experience = try targetExperience(at: time).map { try PersistenceController.journalObject($0, in: context) }
            ?? Experience.create(at: time, in: context)
        let sendsText = !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        try TimedNoteSaving.save(newNote, sendingWebhooksTo: sendsText ? WebhookPreset.defaultPresetObjectIDs() : [])
    }
}
