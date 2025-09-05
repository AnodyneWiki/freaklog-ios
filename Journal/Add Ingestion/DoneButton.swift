import SwiftUI

struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        Button("Done") {
            action()
        }.font(.headline)
    }
}

#Preview {
    DoneButton {}
}
