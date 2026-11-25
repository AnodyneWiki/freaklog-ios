import CoreData
import SwiftUI

struct EditColorsScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    @State private var companionToEdit: SubstanceCompanion?
    @State private var search = ""
    @State private var isImportingPalette = false

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
                    Text(substanceCompanions.isEmpty ? "No substances configured yet" : "No matching substances")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(companions) { companion in
                        Button(action: {
                            companionToEdit = companion
                        }, label: {
                            CompanionRow(
                                name: PersistenceController.shared.displayName(for: companion.substanceNameUnwrapped),
                                color: companion.color.swiftUIColor,
                                isHidden: companion.isHiddenInTimeline
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
        .navigationTitle("Substance Colors & Visibility")
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
    @State private var hidesTimeline: Bool
    @State private var showsSaveError = false
    @Environment(\.dismiss) private var dismiss

    init(companion: SubstanceCompanion, usedColors: [SubstanceColor]) {
        self.companion = companion
        self.usedColors = usedColors
        _color = State(initialValue: companion.color)
        _hidesTimeline = State(initialValue: companion.isHiddenInTimeline)
    }

    var body: some View {
        ColorPickerScreen(selectedColor: $color, usedColors: usedColors, hidesTimeline: $hidesTimeline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        do {
                            let context = try PersistenceController.shared.journalEditContext()
                            let editable = try PersistenceController.journalObject(companion, in: context)
                            editable.colorAsText = color.rawValue
                            editable.isHiddenInTimeline = hidesTimeline
                            try context.save()
                            dismiss()
                        } catch {
                            showsSaveError = true
                        }
                    }
                }
            }
            .alert("Couldn’t Save Substance Settings", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            }
    }
}

struct SubstanceTimelineVisibilityToggle: View {
    let substanceName: String
    @FetchRequest private var companions: FetchedResults<SubstanceCompanion>
    @State private var showsSaveError = false

    init(substanceName: String) {
        self.substanceName = substanceName
        let request = PersistenceController.substanceCompanionsRequest()
        request.predicate = NSPredicate(format: "substanceName == %@", substanceName)
        _companions = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        Toggle(isOn: Binding(get: {
            companions.contains(where: \.isHiddenInTimeline)
        }, set: save)) {
            Label("Hide Timeline by Default", systemImage: "eye.slash")
        }
        .alert("Couldn’t Update the Timeline", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func save(_ isHidden: Bool) {
        do {
            let context = try PersistenceController.shared.journalEditContext()
            let request = PersistenceController.substanceCompanionsRequest()
            request.predicate = NSPredicate(format: "substanceName == %@", substanceName)
            let records = try context.fetch(request)
            if records.isEmpty, isHidden {
                let companion = SubstanceCompanion(context: context)
                companion.substanceName = substanceName
                companion.colorAsText = SubstanceColor.suggested(
                    avoiding: try context.fetch(PersistenceController.substanceCompanionsRequest()).map(\.color)
                ).rawValue
                companion.isHiddenInTimeline = true
            }
            for record in records { record.isHiddenInTimeline = isHidden }
            try context.save()
        } catch {
            showsSaveError = true
        }
    }
}

struct CompanionRow: View {
    let name: String
    let color: Color
    var isHidden = false

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if isHidden {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hidden from timelines")
            }
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
