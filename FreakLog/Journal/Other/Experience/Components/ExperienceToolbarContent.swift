import SwiftUI

struct ExperienceToolbarContent: View {
    @ObservedObject var experience: Experience
    @Binding var sheetToShow: ExperienceScreen.SheetOption?
    @Binding var isShowingDeleteConfirmation: Bool
    let canAddIngestion: Bool
    let addIngestion: () -> Void

    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isAssistantEnabledKey) private var isAssistantEnabled = false

    var body: some View {
        Group {
            Menu {
                if canAddIngestion {
                    Button(action: addIngestion) {
                        Label("Add Ingestion", systemImage: "plus")
                    }
                }
                Button {
                    sheetToShow = .addTimedNote
                } label: {
                    Label("Add Timed Note", systemImage: "note.text")
                }
                if isEyeOpen {
                    Button {
                        sheetToShow = .addRating
                    } label: {
                        Label("Add Rating", systemImage: "plus.forwardslash.minus")
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            Menu {
                if isAssistantEnabled {
                    Section {
                        Button {
                            sheetToShow = .assistant(prompt: AssistantChat.summaryPrompt)
                        } label: {
                            Label("Summarize Session", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            sheetToShow = .assistant(prompt: nil)
                        } label: {
                            Label("Ask Assistant", systemImage: "text.bubble")
                        }
                    }
                }
                Button {
                    sheetToShow = .shareExperience
                } label: {
                    Label("Share Experience", systemImage: "square.and.arrow.up")
                }
                Button {
                    sheetToShow = .editNotes
                } label: {
                    Label("Edit Notes", systemImage: "pencil")
                }
                Button {
                    sheetToShow = .editTitle
                } label: {
                    Label("Edit Title", systemImage: "pencil")
                }
                let isFavorite = experience.isFavorite
                Button {
                    experience.isFavorite = !isFavorite
                    try? PersistenceController.shared.viewContext.save()
                } label: {
                    if isFavorite {
                        Label("Unfavorite", systemImage: "star.fill")
                    } else {
                        Label("Mark Favorite", systemImage: "star")
                    }
                }
                if experience.location == nil {
                    Button {
                        sheetToShow = .addLocation
                    } label: {
                        Label("Add Location", systemImage: "plus")
                    }
                }
                Button(role: .destructive) {
                    isShowingDeleteConfirmation.toggle()
                } label: {
                    Label("Delete Experience", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}
