import SwiftUI

struct ColorPickerScreen: View {
    @Binding var selectedColor: SubstanceColor
    // Colors already taken by other substances or notes, listed after the unused ones
    let usedColors: [SubstanceColor]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let alreadyUsedColors = Set(usedColors).sorted()
        let otherColors = SubstanceColor.unused(avoiding: usedColors)
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
        ColorPickerScreen(selectedColor: .constant(.purple), usedColors: [.blue, .red, .orange])
    }
}
