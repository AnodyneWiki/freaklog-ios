import SwiftUI

struct EditColorsScreen: View {
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    var substanceCompanions: FetchedResults<SubstanceCompanion>

    var alreadyUsedColors: [SubstanceColor] {
        Array(Set(substanceCompanions.map { comp in
            comp.color
        })).sorted()
    }

    var otherColors: [SubstanceColor] {
        Array(Set(SubstanceColor.allCases).subtracting(alreadyUsedColors)).sorted()
    }

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
                                name: companion.substanceNameUnwrapped,
                                color: companion.color.swiftUIColor
                            ).foregroundColor(.primary)
                        })
                    }
                }
            }
        }
        .sheet(item: $companionToEdit, content: { companion in
            NavigationStack {
                CompanionColorPickerScreen(
                    companion: companion,
                    alreadyUsedColors: alreadyUsedColors,
                    otherColors: otherColors
                )
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

struct CompanionColorPickerScreen: View {
    let companion: SubstanceCompanion
    let alreadyUsedColors: [SubstanceColor]
    let otherColors: [SubstanceColor]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            if !otherColors.isEmpty {
                Section("Unused Colors") {
                    ForEach(otherColors) { color in
                        button(for: color)
                    }
                }
            }
            if !alreadyUsedColors.isEmpty {
                Section("Used Colors") {
                    ForEach(alreadyUsedColors) { color in
                        button(for: color)
                    }
                }
            }
        }
        .navigationTitle("Choose Color")
    }

    private func button(for color: SubstanceColor) -> some View {
        Button {
            companion.colorAsText = color.rawValue
            PersistenceController.shared.saveViewContext()
            dismiss()
        } label: {
            if companion.color == color {
                HStack {
                    Label(color.name, systemImage: "circle.fill").foregroundColor(color.swiftUIColor)
                    Spacer()
                    Image(systemName: "checkmark")
                }
            } else {
                Label(color.name, systemImage: "circle.fill").foregroundColor(color.swiftUIColor)
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
