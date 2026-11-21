import SwiftUI

struct ChooseDateScreenContent: View {
    @Binding var date: Date
    let finish: () -> Void
    let cancel: () -> Void
    let isShowingColorPicker: Bool
    let substanceName: String
    @Binding var selectedColor: SubstanceColor
    let usedColors: [SubstanceColor]

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
                            usedColors: usedColors
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
        ChooseDateScreenContent(
            date: .constant(Date.now),
            finish: {},
            cancel: {},
            isShowingColorPicker: true,
            substanceName: "MDMA",
            selectedColor: .constant(.blue),
            usedColors: [.green, .pink]
        )
    }
}
