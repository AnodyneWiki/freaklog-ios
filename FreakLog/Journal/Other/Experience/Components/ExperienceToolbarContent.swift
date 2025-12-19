import SwiftUI

struct ExperienceToolbarContent: View {
    @ObservedObject var experience: Experience
    @Binding var saveableTimeDisplayStyle: SaveableTimeDisplayStyle
    @Binding var sheetToShow: ExperienceScreen.SheetOption?
    @Binding var isShowingDeleteConfirmation: Bool
    let addIngestion: () -> Void

    @AppStorage(PersistenceController.isEyeOpenKey2) private var isEyeOpen: Bool = false

    var body: some View {
        Group {
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
