import CoreData
import SwiftUI

struct EditColorsScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    @State private var companionToEdit: SubstanceCompanion?
    @State private var isImportingPalette = false
    @State private var search = ""

    private var visibleCompanions: [SubstanceCompanion] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return substanceCompanions.filter { companion in
            let name = companion.substanceNameUnwrapped
            return query.isEmpty || name.localizedStandardContains(query)
                || PersistenceController.shared.displayName(for: name).localizedStandardContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                let companions = visibleCompanions
                if companions.isEmpty {
                    Text(substanceCompanions.isEmpty ? "No colors added yet" : "No matching substances")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(companions) { companion in
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
        .navigationTitle("Substance Colors")
        .searchable(text: $search, prompt: "Find a substance")
        .toolbar {
            Menu {
                NavigationLink("Share Palette") { PalettePresetExportScreen() }
                Button("Import Palette") { isImportingPalette = true }
            } label: {
                Label("Palette", systemImage: "ellipsis.circle")
            }
        }
        .modifier(JournalPresetImporter(isPresented: $isImportingPalette, scope: .palette))
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
