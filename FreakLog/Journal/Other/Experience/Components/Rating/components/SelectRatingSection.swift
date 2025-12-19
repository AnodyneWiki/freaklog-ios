import SwiftUI

struct SelectRatingSection: View {
    @Binding var selectedRating: ShulginRatingOption

    var body: some View {
        Section("Shulgin Rating") {
            Picker("Shulgin Rating", selection: $selectedRating) {
                ForEach(ShulginRatingOption.allCases, id: \.self) { option in
                    HStack {
                        Text(option.stringRepresentation).font(.title3)
                        Text("(\(option.shortDescription))").foregroundColor(.secondary).font(.caption)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

#Preview {
    List {
        SelectRatingSection(selectedRating: .constant(.plus))
    }
}
