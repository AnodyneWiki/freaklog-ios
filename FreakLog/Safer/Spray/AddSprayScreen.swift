import SwiftUI

struct AddSprayScreen: View {
    @State private var name = ""
    @State private var sizeInMlText = ""
    @State private var sizeInMl: Double?
    @State private var numSpraysText = ""
    @State private var numSprays: Double?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("Spray Name", text: $name)
                        .font(.title)
                        .padding(.vertical, 3)
                }
                Section {
                    VStack {
                        HStack {
                            TextField("Volume", text: $sizeInMlText)
                                .keyboardType(.decimalPad)
                            Text("ml")
                        }
                        .font(.title)
                        TextField("Number of sprays", text: $numSpraysText)
                            .font(.title)
                            .keyboardType(.decimalPad)
                    }.padding(.vertical, 3)
                } header: {
                    Text("Size")
                } footer: {
                    Text("Note: fill it into the spray bottle and count the number of sprays. To make sure the last couple of sprays still work properly use a small spray bottle (5ml) and fill it completely.")
                }.listRowSeparator(.hidden)
            }
            .navigationTitle("Add Spray")
            .onChange(of: numSpraysText) { newValue in
                numSprays = getDouble(from: newValue)
            }
            .onChange(of: sizeInMlText) { newValue in
                sizeInMl = getDouble(from: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let sizeInMl, let numSprays, !name.isEmpty {
                        Button("Save") {
                            save(sizeInMl: sizeInMl, numSprays: numSprays)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func save(sizeInMl: Double, numSprays: Double) {
        let spray = Spray(context: PersistenceController.shared.viewContext)
        spray.creationDate = Date()
        spray.name = name
        spray.contentInMl = sizeInMl
        spray.numSprays = numSprays
        spray.isPreferred = true
        do {
            try PersistenceController.shared.viewContext.save()
        } catch {
            assertionFailure("Failed to save spray")
        }
    }
}

#Preview {
    NavigationStack {
        AddSprayScreen()
    }
}
