import SwiftUI

struct ChooseCustomUnitScreen: View {

    @Binding var customUnit: CustomUnit?
    let customUnits: [CustomUnit]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(customUnits) { unit in
                Button(unit.nameUnwrapped) {
                    customUnit = unit
                    dismiss()
                }
            }
            if customUnit != nil {
                Button("Default") {
                    customUnit = nil
                    dismiss()
                }
            }
        }.navigationTitle("Choose Unit")
    }
}

#Preview {
    ChooseCustomUnitScreen(
        customUnit: .constant(nil),
        customUnits: [
            CustomUnit.estimatePreviewSample,
            CustomUnit.estimatedQuantitativelyPreviewSample
        ]
    )
}
