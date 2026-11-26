import CoreData
import SwiftUI

struct EditColorsScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    @State private var companionToEdit: SubstanceCompanion?

    var body: some View {
        List {
            Section {
                if substanceCompanions.isEmpty {
                    Text("No colors added yet")
                } else {
                    ForEach(substanceCompanions) { companion in
                        Button(action: {
                            companionToEdit = companion
                        }, label: {
                            CompanionRow(
                                name: PersistenceController.shared.displayName(for: companion.substanceNameUnwrapped),
                                color: companion.color.swiftUIColor
                            ).foregroundColor(.primary)
                        })
                    }
                }
            }
        }
        .sheet(item: $companionToEdit, content: { companion in
            NavigationStack {
                EditCompanionColorScreen(companion: companion, usedColors: substanceCompanions.map(\.color))
            }
        })
        .navigationTitle("Edit Colors")
        .onAppear {
            for substanceCompanion in substanceCompanions {
                if substanceCompanion.ingestionsUnwrapped.isEmpty {
                    PersistenceController.shared.viewContext.delete(substanceCompanion)
                }
                PersistenceController.shared.saveViewContext()
            }
        }
    }
}

// Saves the color only with Done, as the system color picker changes it continuously while dragging
private struct EditCompanionColorScreen: View {
    let companion: SubstanceCompanion
    let usedColors: [SubstanceColor]

    @State private var color: SubstanceColor
    @Environment(\.dismiss) private var dismiss

    init(companion: SubstanceCompanion, usedColors: [SubstanceColor]) {
        self.companion = companion
        self.usedColors = usedColors
        _color = State(initialValue: companion.color)
    }

    var body: some View {
        ColorPickerScreen(selectedColor: $color, usedColors: usedColors)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        companion.colorAsText = color.rawValue
                        PersistenceController.shared.saveViewContext()
                        dismiss()
                    }
                }
            }
    }
}

struct CompanionRow: View {
    let name: String
    let color: Color

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Image(systemName: "circle.fill")
                .font(.title2)
                .foregroundColor(color)
        }
    }
}

#Preview {
    List {
        CompanionRow(name: "MDMA", color: .pink)
    }
}
