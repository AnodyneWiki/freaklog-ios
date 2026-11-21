import SwiftUI

struct TimedNoteScreenContent: View {
    @Binding var time: Date
    @Binding var note: String
    @Binding var color: SubstanceColor
    @Binding var isPartOfTimeline: Bool
    let isTextFieldFocused: FocusState<Bool>.Binding
    let usedColors: [SubstanceColor]

    var body: some View {
        Form {
            Section {
                TextEditor(text: $note)
                    .focused(isTextFieldFocused)
                    .autocapitalization(.sentences)
                    .frame(minHeight: 100)
            }
            Section {
                DatePicker(
                    "Time",
                    selection: $time,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
                Toggle("Is part of timeline", isOn: $isPartOfTimeline).tint(.accentColor)
            }
            Section {
                NavigationLink {
                    ColorPickerScreen(
                        selectedColor: $color,
                        usedColors: usedColors
                    )
                } label: {
                    HStack {
                        Text("Note Color")
                        Spacer()
                        Image(systemName: "circle.fill").foregroundColor(color.swiftUIColor)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
