import Foundation

extension IngestionNoteScreen {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var suggestedNotesInOrder = [String]()

        init() {
            suggestedNotesInOrder = PersistenceController.shared.getIngestionsWithNotes(limit: 15)
                .map { $0.noteUnwrapped }.uniqued()
        }
    }
}
