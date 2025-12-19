import SwiftUI

struct RatingExplanationSection: View {
    var body: some View {
        Section("Shulgin Rating Explanation") {
            ForEach(ShulginRatingOption.allCases, id: \.self) { option in
                VStack(alignment: .leading) {
                    Text(option.stringRepresentation).font(.title3)
                    Text(option.description).foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    RatingExplanationSection()
}
