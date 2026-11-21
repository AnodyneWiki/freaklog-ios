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
                ColorPickerScreen(
                    selectedColor: Binding(get: { companion.color }, set: { color in
                        companion.colorAsText = color.rawValue
                        PersistenceController.shared.saveViewContext()
                    }),
                    usedColors: substanceCompanions.map(\.color)
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
