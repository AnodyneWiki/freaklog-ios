import SwiftUI

struct DurationChip: View {
    let name: String
    let text: String
    let color: SubstanceColor

    var body: some View {
        VStack {
            Text(text)
            Text(name)
        }
        .colorBackground(color)
    }
}
