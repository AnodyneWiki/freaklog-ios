import SwiftUI

struct ChooseDateScreenContent: View {
    @Binding var date: Date
    let finish: () -> Void
    let cancel: () -> Void
    let isShowingColorPicker: Bool
    let substanceName: String
    @Binding var selectedColor: SubstanceColor
    let alreadyUsedColors: [SubstanceColor]
    let otherColors: [SubstanceColor]

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .primaryAction) {
                DoneButton(action: finish)
            }
        }
    }

    var screen: some View {
        Form {
            DatePicker("Ingestion Date",
                       selection: $date,
                       displayedComponents: [.date])
                .datePickerStyle(.graphical)
            if isShowingColorPicker {
                Section {
                    NavigationLink {
                        ColorPickerScreen(
                            selectedColor: $selectedColor,
                            alreadyUsedColors: alreadyUsedColors,
                            otherColors: otherColors
                        )
                    } label: {
                        HStack {
                            Text("\(substanceName) Color")
                            Spacer()
                            Image(systemName: "circle.fill").foregroundColor(selectedColor.swiftUIColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Date")
    }
}

#Preview {
    NavigationStack {
        let alreadyUsedColors = [SubstanceColor.green, .pink]
        let otherColors = Array(Set(SubstanceColor.allCases).subtracting(alreadyUsedColors))
        ChooseDateScreenContent(
            date: .constant(Date.now),
            finish: {},
            cancel: {},
            isShowingColorPicker: true,
            substanceName: "MDMA",
            selectedColor: .constant(.blue),
            alreadyUsedColors: alreadyUsedColors,
            otherColors: otherColors
        )
    }
}
