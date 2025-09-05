import SwiftUI

struct EmptySectionForPadding: View {
    var body: some View {
        Section("") {
            EmptyView()
        }
    }
}

#Preview {
    EmptySectionForPadding()
}
