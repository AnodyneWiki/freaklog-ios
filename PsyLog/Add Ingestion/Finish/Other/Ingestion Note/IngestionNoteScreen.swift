import SwiftUI

struct IngestionNoteScreen: View {
    @Binding var note: String
    @StateObject var viewModel = ViewModel()
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
            TextField("Enter Note", text: $note, axis: .vertical)
                .onSubmit {
                    dismiss()
                }
                .submitLabel(.done)
                .focused($textFieldIsFocused)
                .autocapitalization(.sentences)
            if !viewModel.suggestedNotesInOrder.isEmpty {
                Section("Suggestions") {
                    ForEach(viewModel.suggestedNotesInOrder, id: \.self) { suggestedNote in
                        Button {
                            note = suggestedNote
                        } label: {
                            Label(suggestedNote, systemImage: "doc.on.doc").lineLimit(1)
                        }.foregroundColor(.primary)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Ingestion Note")
    }
}

#Preview {
    NavigationStack {
        IngestionNoteScreen(note: .constant(""))
    }
}
