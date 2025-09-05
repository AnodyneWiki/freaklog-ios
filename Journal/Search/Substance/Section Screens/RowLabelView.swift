import SwiftUI

struct RowLabelView: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + " ")
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    RowLabelView(label: "Your label", value: "Your Value")
}
