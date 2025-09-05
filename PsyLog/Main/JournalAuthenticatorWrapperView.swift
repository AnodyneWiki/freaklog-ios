import SwiftUI

struct JournalAuthenticatorWrapperView<Content: View>: View {

    @ObservedObject var authenticator: Authenticator
    let content: () -> Content

    var body: some View {
        ZStack {
            content()
            if authenticator.isStartingUp {
                LockScreen(isEyeOpen: true, isFaceIDEnabled: true)
            } else if authenticator.isLocked {
                LockScreen(isEyeOpen: false, isFaceIDEnabled: authenticator.isFaceIDEnabled)
            }
        }
    }
}
