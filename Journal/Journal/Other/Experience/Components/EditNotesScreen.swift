import SwiftUI

struct EditNotesScreen: View {
    let experience: Experience

    @FocusState private var isTextFieldFocused: Bool
    @State private var notes = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        EditNotesContent(
            notes: $notes,
            isTextFieldFocused: $isTextFieldFocused,
            save: save,
            dismiss: { dismiss() }
        )
        .onAppear {
            notes = experience.textUnwrapped
            if experience.textUnwrapped.isEmpty {
                isTextFieldFocused = true
            }
        }
    }

    private func save() {
        experience.text = notes
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}

struct EditNotesContent: View {
    @Binding var notes: String
    let isTextFieldFocused: FocusState<Bool>.Binding
    let save: () -> Void
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $notes)
                    .focused(isTextFieldFocused)
                    .autocapitalization(.sentences)
                    .frame(minHeight: 300)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    DoneButton {
                        save()
                    }
                }
            }
        }
    }
}

// previews don't work because can't pass FocusState
