import SwiftUI

struct TimedNoteScreenContent: View {
    @Binding var time: Date
    @Binding var note: String
    @Binding var details: TimedNoteDetails
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
            Section {
                DisclosureGroup {
                    Picker("Mood", selection: $details.mood) {
                        Text("Not Recorded").tag(nil as TimedNoteMood?)
                        ForEach(TimedNoteMood.allCases, id: \.self) { mood in
                            Text(mood.title).tag(Optional(mood))
                        }
                    }
                    Picker("Energy", selection: $details.energy) {
                        Text("Not Recorded").tag(nil as TimedNoteEnergy?)
                        ForEach(TimedNoteEnergy.allCases, id: \.self) { energy in
                            Text(energy.title).tag(Optional(energy))
                        }
                    }
                } label: {
                    Label {
                        if details.isEmpty {
                            Text("Add Details")
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Details")
                                Text([details.mood?.title, details.energy?.title].compactMap { $0 }.formatted())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                }
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
