import SwiftUI

struct UnitsPicker: View {
    @Binding var units: String
    @State private var pickerValue = UnitPickerOptions.mg
    @State private var textValue = ""

    var body: some View {
        Group {
            Picker("Units", selection: $pickerValue) {
                ForEach(UnitPickerOptions.allCases, id: \.self) { unit in
                    Text(unit.rawValue)
                        .tag(unit)
                }
            }
            .pickerStyle(.segmented)
            if pickerValue == .custom {
                TextField("Units", text: $textValue, prompt: Text("e.g. cups"))
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
            }
        }
        .listRowSeparator(.hidden)
        .onChange(of: pickerValue) { newValue in
            if newValue != .custom {
                units = newValue.rawValue
            }
        }
        .onChange(of: textValue) { newValue in
            units = newValue
        }
        .task {
            initializePicker()
        }
    }

    private func initializePicker() {
        if let startOption = UnitPickerOptions(rawValue: units) {
            pickerValue = startOption
        } else {
            pickerValue = UnitPickerOptions.custom
            textValue = units
        }
    }
}

#Preview {
    NavigationStack {
        List {
            UnitsPicker(units: .constant(""))
        }
    }
}
