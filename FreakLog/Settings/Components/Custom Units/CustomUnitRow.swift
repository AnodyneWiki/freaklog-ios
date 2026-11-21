import SwiftUI

struct CustomUnitRow: View {
    @ObservedObject var customUnit: CustomUnit

    var body: some View {
        HStack(spacing: 10) {
            ColorRectangle(color: customUnit.color?.swiftUIColor ?? Color.gray)
            VStack(alignment: .leading) {
                Text("\(customUnit.substanceDisplayName), \(customUnit.nameUnwrapped)").font(.headline)
                Text(customUnit.doseOfOneUnitDescription) + Text(" per \(customUnit.unitUnwrapped) \(customUnit.administrationRouteUnwrapped.rawValue)").foregroundColor(.secondary)
                .font(.subheadline)
                if !customUnit.noteUnwrapped.isEmpty {
                    Text(customUnit.noteUnwrapped)
                }
            }
        }
    }
}

#Preview {
    List {
        CustomUnitRow(customUnit: CustomUnit.previewSample)
    }
}
