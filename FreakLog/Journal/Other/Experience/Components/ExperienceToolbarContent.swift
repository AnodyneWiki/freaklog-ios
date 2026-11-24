import SwiftUI

struct ExperienceToolbarContent: View {
    @ObservedObject var experience: Experience
    @Binding var saveableTimeDisplayStyle: SaveableTimeDisplayStyle
    @Binding var sheetToShow: ExperienceScreen.SheetOption?
    @Binding var isShowingDeleteConfirmation: Bool
    let addIngestion: () -> Void

    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen: Bool = false
    @AppStorage(PersistenceController.isAssistantEnabledKey) private var isAssistantEnabled = false

    private var timeDisplayMenu: some View {
        Menu {
            ForEach(SaveableTimeDisplayStyle.allCases) { option in
                Button {
                    withAnimation {
                        saveableTimeDisplayStyle = option
                    }
                } label: {
                    if saveableTimeDisplayStyle == option {
                        Label(option.text, systemImage: "checkmark")
                    } else {
                        Text(option.text)
                    }
                }
            }
        } label: {
            Label("Time Display", systemImage: "timer")
        }
    }

    var body: some View {
        Group {
            // The assistant shares a menu with the time display, so the bar doesn't get another button
            if isAssistantEnabled {
                Menu {
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
                    timeDisplayMenu
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            } else {
                timeDisplayMenu
            }
            Menu {
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
                Label("Edit", systemImage: "pencil")
            }
            if isEyeOpen {
                Menu {
                    if !experience.isCurrent {
                        Button(action: addIngestion) {
                            Label("Add Ingestion", systemImage: "plus")
                        }
                    }
                    Button {
                        sheetToShow = .addRating
                    } label: {
                        Label("Add Rating", systemImage: "plus.forwardslash.minus")
                    }
                    Button {
                        sheetToShow = .addTimedNote
                    } label: {
                        Label("Add Timed Note", systemImage: "note.text")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}
