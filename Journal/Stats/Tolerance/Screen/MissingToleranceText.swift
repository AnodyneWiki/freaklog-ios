import SwiftUI

struct MissingToleranceText: View {
    let substanceNames: [String]

    var body: some View {
        Text("Excluding ") + Text(substanceNames, format: .list(type: .and)) + Text(" because of missing tolerance info")
    }
}

#Preview {
    MissingToleranceText(substanceNames: ["2C-B", "Ketamine"])
}
