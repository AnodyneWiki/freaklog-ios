import SwiftUI

struct AuthenticatorWrapper<Content: View>: View {

    @ObservedObject var authenticator: Authenticator
    
    @ViewBuilder
    let content: Content

    var body: some View {
        if authenticator.isStartingUp {
            LockScreen(isEyeOpen: true, isFaceIDEnabled: true)
        } else if authenticator.isLocked {
            LockScreen(isEyeOpen: false, isFaceIDEnabled: authenticator.isFaceIDEnabled)
        }
        else {
            content
        }
    }
}
