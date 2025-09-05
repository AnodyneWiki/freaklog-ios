import SwiftUI

struct ExperienceTitleScreen: View {
    @Binding var title: String
    @Environment(\.dismiss) var dismiss
    @FocusState private var textFieldIsFocused: Bool

    var body: some View {
        NavigationStack {
            screen.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    doneButton
                }
            }
        }
        .onAppear {
            textFieldIsFocused = true
        }
    }

    private var doneButton: some View {
        DoneButton {
            dismiss()
        }
    }

    private var screen: some View {
        Form {
            TextField("Enter Title", text: $title)
                .onSubmit {
                    dismiss()
                }
                .submitLabel(.done)
                .focused($textFieldIsFocused)
                .autocapitalization(.sentences)
                .autocorrectionDisabled()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Experience Title")
    }
}

#Preview {
    NavigationStack {
        ExperienceTitleScreen(title: .constant(""))
    }
}
