import SwiftUI

// Picks a suggested color, one from the system color picker or a hex code. Changes apply right away.
struct ColorPickerScreen: View {
    @Binding var selectedColor: SubstanceColor
    // Colors already taken by other substances or notes, shown apart from the unused ones
    let usedColors: [SubstanceColor]
    var hidesTimeline: Binding<Bool>?

    @State private var hexText = ""
    // Made once, so a suggestion stays in place after choosing it
    @State private var suggestedColors: [SubstanceColor] = []
    @FocusState private var isHexFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ColorSwatch(color: selectedColor, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedColor.name.localizedCapitalized)
                            .font(.headline)
                        Text(selectedColor.hex)
                            .font(.subheadline.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                ColorPicker("Custom Color", selection: systemPickerColor, supportsOpacity: false)
                LabeledContent("Hex Code") {
                    TextField("#RRGGBB", text: $hexText)
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isHexFieldFocused)
                        .onChange(of: hexText) { text in
                            if let color = SubstanceColor(hex: text), color != selectedColor {
                                selectedColor = color
                            }
                        }
                        .onSubmit {
                            hexText = selectedColor.hex
                        }
                }
            } footer: {
                Text("Enter six hexadecimal digits, like #0A84FF.")
            }
            if !suggestedColors.isEmpty {
                Section {
                    swatchGrid(of: suggestedColors)
                } header: {
                    Text("Suggested")
                } footer: {
                    Text("Easy to tell apart from the colors in use.")
                }
            }
            let colorsInUse = Array(Set(usedColors)).sorted(by: Self.paletteOrder)
            if !colorsInUse.isEmpty {
                Section {
                    swatchGrid(of: colorsInUse)
                } header: {
                    Text("In Use")
                } footer: {
                    Text("Already used by other substances or notes.")
                }
            }
            if let hidesTimeline {
                Section {
                    Toggle("Hide Timeline by Default", isOn: hidesTimeline)
                } footer: {
                    Text("This substance stays in your journal and statistics.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Color")
        .onAppear {
            hexText = selectedColor.hex
            if suggestedColors.isEmpty {
                suggestedColors = SubstanceColor.distinctColors(from: usedColors, count: Self.numberOfSuggestions)
            }
        }
        .onChange(of: selectedColor) { color in
            // Typing a code updates the color; a color chosen elsewhere replaces the code
            if !isHexFieldFocused || SubstanceColor(hex: hexText) != color {
                hexText = color.hex
            }
        }
    }

    private var systemPickerColor: Binding<Color> {
        Binding {
            selectedColor.swiftUIColor
        } set: { color in
            selectedColor = SubstanceColor(color)
        }
    }

    private func swatchGrid(of colors: [SubstanceColor]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(colors) { color in
                Button {
                    isHexFieldFocused = false
                    selectedColor = color
                } label: {
                    ColorSwatch(color: color, size: 32, isSelected: color == selectedColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(color == selectedColor ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private static let numberOfSuggestions = 12

    // Palette colors in palette order, then other codes by code
    private static func paletteOrder(_ lhs: SubstanceColor, _ rhs: SubstanceColor) -> Bool {
        let lhsIndex = SubstanceColor.palette.firstIndex(of: lhs) ?? Int.max
        let rhsIndex = SubstanceColor.palette.firstIndex(of: rhs) ?? Int.max
        return lhsIndex == rhsIndex ? lhs.hex < rhs.hex : lhsIndex < rhsIndex
    }
}

// A filled circle with a hairline edge, so light colors stay visible, and a ring when selected
struct ColorSwatch: View {
    let color: SubstanceColor
    let size: Double
    var isSelected = false

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .frame(width: size, height: size)
            .padding(isSelected ? 3 : 0)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                }
            }
    }
}

#Preview {
    NavigationStack {
        ColorPickerScreen(selectedColor: .constant(.purple), usedColors: [.blue, .red, .orange])
    }
}
