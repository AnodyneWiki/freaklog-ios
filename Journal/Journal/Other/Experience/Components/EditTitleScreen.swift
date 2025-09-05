import SwiftUI

struct EditTitleScreen: View {
    let experience: Experience

    @State private var title = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        EditTitleScreenContent(
            title: $title,
            isTextFieldFocused: $isTextFieldFocused,
            save: save,
            dismiss: { dismiss() }
        )
        .onAppear {
            title = experience.titleUnwrapped
            isTextFieldFocused = true
        }
    }

    private func save() {
        experience.title = title
        PersistenceController.shared.saveViewContext()
        dismiss()
    }
}

struct EditTitleScreenContent: View {
    @Binding var title: String
    let isTextFieldFocused: FocusState<Bool>.Binding
    let save: () -> Void
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Enter Title", text: $title, axis: .vertical)
                    .onSubmit {
                        save()
                    }
                    .submitLabel(.done)
                    .focused(isTextFieldFocused)
                    .autocapitalization(.sentences)
                    .autocorrectionDisabled()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Title")
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

// can't have preview because can't pass FocusState
