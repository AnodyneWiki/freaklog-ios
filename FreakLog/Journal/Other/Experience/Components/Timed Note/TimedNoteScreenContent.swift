import SwiftUI

struct TimedNoteScreenContent: View {
    @Binding var time: Date
    @Binding var note: String
    @Binding var color: SubstanceColor
    @Binding var isPartOfTimeline: Bool
    let isTextFieldFocused: FocusState<Bool>.Binding
    let usedColors: [SubstanceColor]
    // Only new notes are sent, so only adding one shows the toggle
    var isShowingWebhookToggle = false

    @AppStorage(PersistenceController.sendWebhooksEnabledKey) private var isSendingWebhooks = false

    var body: some View {
        Form {
            Section("Note") {
                TextEditor(text: $note)
                    .focused(isTextFieldFocused)
                    .autocapitalization(.sentences)
                    .frame(minHeight: 100)
                    .accessibilityLabel("Note")
            }
            Section("When") {
                DatePicker(
                    "Time",
                    selection: $time,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }
            Section("Display") {
                Toggle("Show in Timeline", isOn: $isPartOfTimeline).tint(.accentColor)
                NavigationLink {
                    ColorPickerScreen(
                        selectedColor: $color,
                        usedColors: usedColors
                    )
                } label: {
                    LabeledContent {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(color.swiftUIColor)
                            .accessibilityLabel(Text(color.name))
                    } label: {
                        Text("Note Color")
                    }
                }
            }
            if isShowingWebhookToggle {
                Section {
                    Toggle("Send Webhooks", isOn: $isSendingWebhooks).tint(.accentColor)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
