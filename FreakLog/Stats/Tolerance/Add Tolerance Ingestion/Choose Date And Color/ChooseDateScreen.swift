import SwiftUI

struct ChooseDateScreen: View {
    let substanceName: String
    let cancel: () -> Void
    let finish: (SubstanceAndDay) -> Void

    @State private var date = Date()
    @State private var selectedColor = SubstanceColor.red
    @FetchRequest(fetchRequest: PersistenceController.substanceCompanionsRequest())
    private var substanceCompanions: FetchedResults<SubstanceCompanion>

    private var doesSubstanceAlreadyHaveColor: Bool {
        substanceCompanions.contains { companion in
            companion.substanceName == substanceName
        }
    }

    private var usedColors: [SubstanceColor] {
        substanceCompanions.map(\.color)
    }

    var body: some View {
        ChooseDateScreenContent(
            date: $date,
            finish: {
                if !doesSubstanceAlreadyHaveColor {
                    saveSubstanceCompanion()
                }
                finish(SubstanceAndDay(substanceName: substanceName, day: date))
            },
            cancel: cancel,
            isShowingColorPicker: !doesSubstanceAlreadyHaveColor,
            substanceName: substanceName,
            selectedColor: $selectedColor,
            usedColors: usedColors
        ).onAppear {
            selectedColor = SubstanceColor.suggested(avoiding: usedColors)
        }
    }

    private func saveSubstanceCompanion() {
        let context = PersistenceController.shared.viewContext
        let companion = SubstanceCompanion(context: context)
        companion.substanceName = substanceName
        companion.colorAsText = selectedColor.rawValue
        try? context.save()
    }
}
