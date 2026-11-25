import SwiftUI

struct AuthenticatorWrapper<Content: View>: View {

    @ObservedObject var authenticator: Authenticator
    
    @ViewBuilder
    let content: Content

    var body: some View {
        if authenticator.isStartingUp {
            LockScreen(isFaceIDEnabled: true)
        } else if authenticator.isLocked {
            LockScreen(
                isFaceIDEnabled: authenticator.isFaceIDEnabled,
                isAuthenticating: authenticator.isAuthenticating,
                unlock: authenticator.retryUnlock
            )
        }
        else {
            content
        }
    }
}
