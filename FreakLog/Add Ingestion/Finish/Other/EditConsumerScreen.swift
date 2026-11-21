import SwiftUI

struct EditConsumerScreen: View {
    @Binding var consumerName: String

    @State private var consumerNamesInOrder: [String] = []

    private var filteredNames: [String] {
        consumerNamesInOrder.filter { name in
            if !consumerName.isEmpty {
                name.lowercased().hasPrefix(consumerName.lowercased())
            } else {
                true
            }
        }
    }

    var body: some View {
        EditConsumerScreenContent(
            consumerName: $consumerName,
            consumerNamesInOrder: filteredNames
        )
        .onAppear {
            let sortedIngestions = PersistenceController.shared.getRecentIngestions(limit: 300)
            consumerNamesInOrder = sortedIngestions
                .compactMap { Ingestion.storedConsumerName($0.consumerNameUnwrapped) }
                .uniqued()
        }
    }
}

private struct EditConsumerScreenContent: View {
    @Binding var consumerName: String
    let consumerNamesInOrder: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Consumer name", text: $consumerName, prompt: Text("Enter name"))
                        .autocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section {
                    if !consumerName.isEmpty {
                        Button {
                            consumerName = ""
                            dismiss()
                        } label: {
                            Label("You", systemImage: "person")
                        }
                    }

                    ForEach(consumerNamesInOrder, id: \.self) { otherName in
                        Button {
                            consumerName = otherName
                            dismiss()
                        } label: {
                            Label(otherName, systemImage: "person")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    DoneButton {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Consumer")
        }
    }
}

#Preview {
    EditConsumerScreenContent(
        consumerName: .constant("Dave"),
        consumerNamesInOrder: ["Andrea", "Paula", "Eric"]
    )
}
