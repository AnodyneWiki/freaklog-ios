import SwiftUI

struct ColorPickerScreen: View {
    @Binding var selectedColor: SubstanceColor
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
        }.navigationTitle("Choose Color")
    }

    private func button(for color: SubstanceColor) -> some View {
        Button {
            selectedColor = color
            dismiss()
        } label: {
            if selectedColor == color {
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

#Preview {
    NavigationStack {
        let alreadyUsed = [SubstanceColor.blue, .red, .orange]
        ColorPickerScreen(
            selectedColor: .constant(.purple),
            alreadyUsedColors: alreadyUsed,
            otherColors: Array(Set(SubstanceColor.allCases).subtracting(alreadyUsed))
        )
    }
}
